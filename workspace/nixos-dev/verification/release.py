#!/usr/bin/env python3
"""Local verification, fast-forward integration and activation. Effects are not retried."""
import argparse
from contextlib import contextmanager
import fcntl
import json
from pathlib import Path
import socket
import subprocess
import sys


def run(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def git(repo, *args):
    return run(['git', '-C', str(repo), *args])


def revision(repo, ref):
    return git(repo, 'rev-parse', '--verify', ref + '^{commit}')


def clean(repo):
    if git(repo, 'status', '--porcelain'):
        raise ValueError('Commit explicitly staged changes first; the checkout must be clean')


def active_revision(lane):
    # Standalone HM has its own generation; NixOS revision cannot identify it.
    if lane == 'home':
        return None
    try:
        return json.loads(run(['nixos-version', '--json']))['configurationRevision'] or None
    except (OSError, subprocess.CalledProcessError, KeyError, json.JSONDecodeError):
        return None


def generation(lane):
    paths = ([Path('/run/current-system')] if lane == 'system' else
             [Path.home() / '.local/state/nix/profiles/home-manager', Path.home() / '.nix-profile'])
    return tuple(str(path.resolve()) for path in paths)


def changed(repo, candidate, baselines):
    if not baselines or any(not baseline for baseline in baselines):
        return None
    paths = set()
    for baseline in baselines:
        try:
            base = revision(repo, baseline)
            # No rename inference: both old and new paths participate; deletions broaden.
            records = git(repo, 'diff', '--no-renames', '--name-status', base, candidate).splitlines()
        except subprocess.CalledProcessError:
            return None
        for record in records:
            status, path = record.split('\t', 1)
            if status != 'M':
                return None
            paths.add(path)
    return paths


def select(inventory, paths):
    required = {name for name, entry in inventory.items() if entry['kind'] in ('governance', 'shared')}
    if paths is None:
        return sorted(inventory), 'unknown deployed baseline or added/deleted input'
    owners = set()
    for path in paths:
        # A leaf desktop change has no system setters outside its home owner.
        # Keep mail's integrated HM consumers and the shared keymap in that scope.
        if path.startswith('domains/home/apps/waybar/'):
            owners.update(('domains/home', 'domains/home/keymap', 'domains/mail'))
        elif '/verification/' in path and path.startswith('domains/'):
            owner = path.split('/verification/')[0]
            if not any(entry['owner'] == owner for entry in inventory.values()):
                return sorted(inventory), 'unmapped verification owner'
            owners.add(owner)
        else:
            # Cross-domain configuration, locks, modules and unknown inputs broaden.
            return sorted(inventory), 'shared or uncertain dependency: ' + path
    required.update(name for name, entry in inventory.items() if entry['owner'] in owners)
    return sorted(required), 'governance, shared contracts and affected owners'


def uri(repo, candidate=None):
    return f'git+file://{repo}?rev={candidate}' if candidate else f'path:{repo}'


def inventory_for(source):
    return json.loads(run(['nix', 'eval', '--json', source + '#lib.verification']))


def build_checks(source, names, nix_args=()):
    subprocess.run(['nix', 'build', '--no-link', *nix_args,
                    *[source + '#checks.x86_64-linux.' + n for n in names]], check=True)


def snapshot(repo, candidate, lane):
    clean(repo)
    return (revision(repo, 'HEAD'), revision(repo, 'main'), candidate, lane,
            active_revision(lane), generation(lane))


def unchanged(repo, token):
    if snapshot(repo, token[2], token[3]) != token:
        raise ValueError('Candidate, main or active generation changed; verification is stale')


@contextmanager
def release_lock(repo):
    common = Path(git(repo, 'rev-parse', '--git-common-dir'))
    if not common.is_absolute():
        common = repo / common
    with (common / 'hwc-release.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def verify(repo, candidate, target, lane, full=False, nix_args=()):
    token = snapshot(repo, candidate, lane)
    if lane == 'home':
        baseline = active_revision('system')
        if not baseline:
            raise ValueError('Cannot establish pending system changes; use the system lane')
        pending = git(repo, 'diff', '--name-only', revision(repo, baseline), candidate).splitlines()
        for path in pending:
            home_only = (path.startswith('domains/home/')
                         or (path.startswith(('profiles/', 'machines/')) and path.endswith('/home.nix'))
                         or path.endswith('.md'))
            if not home_only:
                raise ValueError('Pending system or mixed change requires the system lane: ' + path)
    source = uri(repo, candidate)
    inventory = inventory_for(source)
    names, reason = select(inventory, None if full else changed(repo, candidate, [token[1], token[4]]))
    print(json.dumps({'candidate': candidate, 'target': target, 'lane': lane,
                      'reason': reason, 'checks': names}), flush=True)
    build_checks(source, names, nix_args)
    assembly = (f'homeConfigurations."eric@{target}".activationPackage' if lane == 'home'
                else f'nixosConfigurations.{target}.config.system.build.toplevel')
    output = run(['nix', 'build', '--no-link', '--print-out-paths', *nix_args, source + '#' + assembly])
    unchanged(repo, token)
    return token, output.splitlines()[-1]


def release(repo, candidate, target, lane, action, full=False, nix_args=()):
    # Authority stays local: remote hosts run this command through SSH on that host.
    if target != socket.gethostname():
        raise ValueError('Run release on the target host; do not build another host toplevel here')
    if git(repo, 'branch', '--show-current') != 'main':
        raise ValueError('Integrate and activate from the primary main checkout')
    with release_lock(repo):
        token, output = verify(repo, candidate, target, lane, full, nix_args)
        # The fast-forward check precedes changing runtime checkout files.
        subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', token[0], candidate], check=True)
        unchanged(repo, token)
        if token[0] != candidate:
            subprocess.run(['git', '-C', str(repo), 'merge', '--ff-only', candidate], check=True)
        if revision(repo, 'HEAD') != candidate or revision(repo, 'main') != candidate:
            raise ValueError('Main moved during integration; refusing activation')
        clean(repo)
        if active_revision(lane) != token[4] or generation(lane) != token[5]:
            raise ValueError('Active generation changed during integration; rerun verification')
        if action == 'merge' or action == 'build':
            return
        if lane == 'home':
            if action != 'switch':
                raise ValueError('Standalone Home Manager supports switch only')
            subprocess.run([output + '/activate'], check=True)
        else:
            subprocess.run(['sudo', 'env', 'HOME=/root', 'nixos-rebuild', action,
                            '--flake', uri(repo, candidate) + '#' + target, *nix_args], check=True)
        print(f'{candidate}: activated {target} via {lane}; live service health still requires inspection')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('governance', 'plan', 'verify', 'deploy'))
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--candidate', default='HEAD')
    parser.add_argument('--target', default=socket.gethostname())
    parser.add_argument('--lane', choices=('system', 'home'), default='system')
    parser.add_argument('--action', choices=('merge', 'build', 'test', 'switch'), default='switch')
    parser.add_argument('--full', action='store_true')
    args, nix_args = parser.parse_known_args()
    allowed = {'--show-trace', '--refresh', '--verbose', '--print-build-logs', '-L', '--keep-going'}
    if any(arg not in allowed for arg in nix_args):
        parser.error('Unsupported Nix argument; target, flake and output cannot be overridden')
    repo = args.repo.resolve()
    if args.command == 'governance':
        source = uri(repo)
        inventory = inventory_for(source)
        names = sorted(n for n, entry in inventory.items() if entry['kind'] == 'governance')
        if not names:
            raise ValueError('No registered governance checks')
        build_checks(source, names)
        return
    candidate = revision(repo, args.candidate)
    if args.command == 'plan':
        inventory = inventory_for(uri(repo, candidate))
        names, reason = select(inventory, changed(repo, candidate, [revision(repo, 'main'), active_revision(args.lane)]))
        print(json.dumps({'candidate': candidate, 'target': args.target, 'lane': args.lane,
                          'checks': names, 'reason': reason}, indent=2))
    elif args.command == 'verify':
        if args.target != socket.gethostname():
            raise ValueError('Verify the assembly on its target host')
        verify(repo, candidate, args.target, args.lane, args.full, nix_args)
    else:
        release(repo, candidate, args.target, args.lane, args.action, args.full, nix_args)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'verification refused: {error}')
