#!/usr/bin/env python3
"""Canonical wired charter rules. Exit 0 clean, 1 violation, 2 tool error."""
import argparse
import json
import os
from pathlib import Path
import re

LAWS = (1, 2, 4, 5, 7, 10, 12, 14, 16)
README_SECTIONS = ('Purpose', 'Boundaries', 'Structure', 'Changelog')


def readme_requirements(root):
    domains = root / 'domains'
    directories = list(domains.glob('*/'))
    directories += list((domains / 'server/containers').glob('*/'))
    directories += list((domains / 'home/apps').glob('*/'))
    # The wired law checks module presence and top-level section headings.
    return {directory: README_SECTIONS if directory.parent == domains else ()
            for directory in sorted(directories) if directory.name != '_shared'}


def files(root, directory):
    base = root / directory
    if not base.is_dir():
        raise FileNotFoundError(base)
    result = {}
    def unreadable(error):
        raise error
    for parent, dirs, names in os.walk(base, onerror=unreadable):
        dirs[:] = sorted(d for d in dirs if d != '.git')
        for name in sorted(names):
            path = Path(parent) / name
            if path.suffix in ('.nix', '.md'):
                result[path.relative_to(root).as_posix()] = path.read_text()
    return result


def inspect(root, law):
    domain = files(root, 'domains')
    # These functions consume configurations; layout.py keeps them out of modules.
    production = {p: s for p, s in domain.items()
                  if p.endswith('.nix') and '/verification/' not in p}
    hits = []
    def match(sources, pattern, flags=0, reject=None):
        for path, source in sources.items():
            for number, line in enumerate(source.splitlines(), 1):
                if re.search(pattern, line, flags) and not (reject and re.search(reject, line)):
                    hits.append(f'{path}:{number}:{line.strip()}')
    if law == 1:
        match({p: s for p, s in production.items() if p.startswith('domains/home/')},
              r'osConfig\.', reject=r'osConfig\.[a-zA-Z0-9_.]+ or |attrByPath|osConfig \?|lib\.mkIf isNixOS|#')
    elif law == 2:
        match(production, r'hwc\.(services|features|alerts|infrastructure)\.')
    elif law == 4:
        match(production, r'PGID\s*=\s*"?1000"?\s*;')
    elif law == 5:
        match({p: s for p, s in production.items() if not p.endswith('/mkContainer.nix')
               and 'HWC-EXCEPTION(Law 5)' not in s}, r'oci-containers\.containers\.')
    elif law == 7:
        match({p: s for p, s in production.items()
               if re.fullmatch(r'domains/home/[^/]+/index\.nix', p)}, r'import.*sys\.nix')
    elif law == 10:
        hits.extend(p for p in domain if Path(p).name == 'options.nix')
        match({p: s for p, s in production.items()
               if Path(p).name not in ('index.nix', 'sys.nix')
               and p != 'domains/paths/paths.nix' and 'HWC-EXCEPTION(Law 10)' not in s},
              r'^[^#]*=\s*(lib\.)?mk(Option|EnableOption)\b')
    elif law == 12:
        for directory, sections in readme_requirements(root).items():
            readme = directory / 'README.md'
            if not readme.is_file():
                hits.append(f'Missing: {readme.relative_to(root)}')
                continue
            source = readme.read_text()
            for section in sections:
                if not re.search(r'^## ' + section, source, re.M):
                    hits.append(f'{readme.relative_to(root)}: missing {section}')
    elif law == 14:
        match({'flake.nix': (root / 'flake.nix').read_text()}, r'github:eriqueo/nixos[-]hwc')
    elif law == 16:
        profiles = files(root, 'profiles')
        match({p: s for p, s in profiles.items() if not p.endswith('/README.md')},
              r'mkDerivation|fetchurl|writeShellScript')
        match({p: s for p, s in profiles.items() if not p.endswith('/README.md')},
              r'\b(laptop|xps|kids|firestick|hwc-home)\b', re.I)
        match(profiles, r'import.*profiles/|mkOption|mkEnableOption')
    return hits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--law', type=int, choices=LAWS, action='append')
    args = parser.parse_args()
    status = 0
    for law in args.law or LAWS:
        try:
            hits = inspect(args.root, law)
            result = {'law': law, 'status': 'violation' if hits else 'clean', 'findings': hits}
            status = max(status, int(bool(hits)))
        except (OSError, UnicodeError) as error:
            result = {'law': law, 'status': 'tool-error', 'error': str(error)}
            status = 2
        print(json.dumps(result))
    return status


if __name__ == '__main__':
    raise SystemExit(main())
