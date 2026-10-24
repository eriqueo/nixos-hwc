"""One Scout SQL/profile producer; only the composition root binds host ports.

CRITICAL: complete current plus one previous bundle, at most one pending slot.
Each bundle is bounded by config.maxBundleBytes. Borg owns archive retention.
The old SQL-only artifact is retained separately, never deleted by this producer.
"""
import ctypes
import errno
import fcntl
import hashlib
import json
import os
import pathlib
import pwd
import selectors
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import urllib.request

class BackupError(RuntimeError):
    def __init__(self, code):
        super().__init__(code)
        self.code = code

def stream_port(command, output, deadline, max_bytes, source=None):
    capture = output != subprocess.DEVNULL
    child = subprocess.Popen(command, stdin=source or subprocess.DEVNULL,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True)
    count, digest = 0, hashlib.sha256()
    try:
        if capture:
            with selectors.DefaultSelector() as events:
                events.register(child.stdout, selectors.EVENT_READ)
                while True:
                    left = deadline - time.monotonic()
                    if left <= 0 or not events.select(left):
                        raise BackupError('port_deadline')
                    block = os.read(child.stdout.fileno(), min(65536, max_bytes - count + 1))
                    if not block:
                        break
                    count += len(block)
                    if count > max_bytes:
                        raise BackupError('bundle_byte_limit')
                    output.write(block)
                    digest.update(block)
        if child.wait(timeout=max(.001, deadline - time.monotonic())) != 0:
            raise BackupError('port_failed')
        return {'bytes': count, 'sha256': digest.hexdigest()}
    except BaseException:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
        raise
    finally:
        if child.stdout is not None:
            child.stdout.close()

def snapshot(destination, command, max_bytes=536870912, timeout_seconds=120):
    os.umask(0o077)
    root = destination.parent
    if root.is_symlink():
        raise RuntimeError('snapshot directory must not be a symlink')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    deadline = time.monotonic() + timeout_seconds
    with (root / 'snapshot.lock').open('a+b') as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        pending = root / 'pending.dump'
        pending.unlink(missing_ok=True)
        def run(args, output, source=None):
            return stream_port(command + args, output, deadline, max_bytes, source)
        try:
            with pending.open('xb') as output:
                os.fchmod(output.fileno(), 0o600)
                run(['sh', '-c', 'export PGOPTIONS="-c statement_timeout=' + str(min(90000, max(1, int(timeout_seconds * 1000)))) + ' -c lock_timeout=1000"; exec pg_dump --format=custom --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"'], output)
                output.flush()
                os.fsync(output.fileno())
            if not 5 < pending.stat().st_size <= max_bytes:
                raise RuntimeError('member database snapshot exceeds bound or is empty')
            with pending.open('rb', buffering=0) as source:
                if source.read(5) != b'PGDMP':
                    raise RuntimeError('member database snapshot has invalid format')
                source.seek(0)
                run(['pg_restore', '--list'], subprocess.DEVNULL, source)
            os.replace(pending, destination)
            fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            try: os.fsync(fd)
            finally: os.close(fd)
        finally:
            pending.unlink(missing_ok=True)

def read_json(path):
    return json.loads(pathlib.Path(path).read_text())

def write_json(path, value):
    path = pathlib.Path(path)
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as out:
        os.fchmod(out.fileno(), 0o600)
        json.dump(value, out, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())
    os.replace(temporary, path)

def command(args, timeout=2):
    # Outputs stay in this private process. Do not expose inspect environment.
    child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    try:
        output, _ = child.communicate(timeout=timeout)
        if child.returncode != 0:
            raise BackupError('port_failed')
        if len(output) > 1048576:
            raise BackupError('port_output_limit')
        return output.decode().strip()
    except BaseException:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
        raise
    finally:
        child.stdout.close()

def podman(config, *args):
    return command(config['podman'] + list(args))

def container(config, name):
    items = json.loads(podman(config, 'inspect', name))
    if len(items) != 1:
        raise BackupError('container_identity')
    return items[0]

def identity(pid):
    proc = pathlib.Path('/proc') / str(pid)
    fields = (proc / 'stat').read_text().split(') ', 1)[1].split()
    relative = (proc / 'cgroup').read_text().strip().split('::', 1)[1]
    return {'pid': pid, 'start': fields[19],
            'cgroup': str(pathlib.Path('/sys/fs/cgroup') / relative.lstrip('/'))}

def assert_identity(state):
    current = identity(state['identity']['pid'])
    if current != state['identity']:
        raise BackupError('process_identity_changed')
    leaf = pathlib.Path(current['cgroup'])
    scope = leaf.parent
    if leaf.name != 'container' or scope.name != 'libpod-' + state['cid'] + '.scope':
        raise BackupError('cgroup_identity')
    return scope, leaf

def thaw(config, state_file):
    if not state_file.exists():
        return
    state = read_json(state_file)
    if state['phase'] == 'unpaused':
        return
    scope, leaf = assert_identity(state)
    if not state.get('pauseRequested'):
        state['phase'] = 'unpaused'
        write_json(state_file, state)
        return
    used_fallback = False
    try:
        item = container(config, state['cid'])
        if item['Id'] != state['cid'] or item['State']['Pid'] != state['identity']['pid']:
            raise BackupError('container_identity')
        if item['State']['Paused']:
            podman(config, 'unpause', state['cid'])
    except (BackupError, OSError, subprocess.SubprocessError):
        # A timeout/error of Podman must not strand the running application.
        # Only this exact live process's own container cgroup can be thawed.
        assert_identity(state)
        for path in [scope, leaf]:
            (path / 'cgroup.freeze').write_text('0')
        state['phase'] = 'kernel-thawed'
        state['kernelFallbackUsed'] = True
        write_json(state_file, state)
        used_fallback = True
        # Unpause is idempotent by construction. One bounded reconciliation,
        # without a retry loop, repairs Podman's paused metadata when possible.
        try:
            podman(config, 'unpause', state['cid'])
        except (BackupError, OSError, subprocess.SubprocessError):
            raise BackupError('thaw_metadata_recovery_required')
    for path in [scope, leaf]:
        if (path / 'cgroup.freeze').read_text().strip() != '0':
            raise BackupError('cgroup_still_frozen')
    item = container(config, state['cid'])
    if item['State']['Paused'] or item['State']['Pid'] != state['identity']['pid']:
        raise BackupError('thaw_metadata_recovery_required')
    state['phase'] = 'unpaused'
    write_json(state_file, state)
    if used_fallback:
        raise BackupError('thaw_fallback_used')

def pg(config, sql):
    return json.loads(command(config['pg'] + ['sh', '-c',
        'exec psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" -qAt -v ON_ERROR_STOP=1 -c "$1"',
        'snapshot', 'SET default_transaction_read_only=on; SET statement_timeout=1000; ' + sql]))

def quiescent(config):
    value = pg(config, """SELECT json_build_object(
        'jobs',(SELECT count(*) FROM pipeline_jobs WHERE state IN ('running','queued','interrupted','held_uncertain')),
        'inline',(SELECT count(*) FROM pipeline_inline_owner),
        'transactions',(SELECT count(*) FROM pg_stat_activity
            WHERE datname=current_database() AND backend_type='client backend'
            AND pid<>pg_backend_pid() AND state IS DISTINCT FROM 'idle'))""")
    if any(value.values()):
        raise BackupError('instance_busy')
    rows = podman(config, 'top', config['app'], 'hpid', 'comm').splitlines()[1:]
    names = [line.split(None, 1)[1] for line in rows]
    if not names or any(name not in ['node', 'podman-init'] for name in names):
        raise BackupError('browser_or_other_writer_active')

def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)

def publish(root):
    pending, current, previous = [root / name for name in ['pending', 'current', 'previous']]
    if not (pending / 'manifest.json').is_file():
        raise BackupError('incomplete_bundle')
    if any(path.is_symlink() for path in [pending, current, previous]):
        raise BackupError('bundle_symlink')
    sync_dir(pending)
    if current.exists():
        # Exchange never leaves readers without a complete current directory.
        libc = ctypes.CDLL(None, use_errno=True)
        libc.renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        if libc.renameat2(-100, os.fsencode(pending), -100, os.fsencode(current), 2) != 0:
            raise OSError(ctypes.get_errno(), 'atomic bundle exchange failed')
        if previous.exists():
            shutil.rmtree(previous)
        os.rename(pending, previous)
    else:
        os.rename(pending, current)
    sync_dir(root)

def create_bundle(config, root, state_file, invocation):
    os.umask(0o077)
    if os.getuid() != config['uid'] or pwd.getpwnam(config['user']).pw_uid != config['uid']:
        raise BackupError('account_identity')
    if root.is_symlink() or root.resolve() != pathlib.Path(config['destination']):
        raise BackupError('snapshot_root')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    if shutil.disk_usage(root).free < config['minFreeBytes']:
        raise BackupError('disk_headroom')
    with (root / 'snapshot.lock').open('a+b') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Repair only a prior invocation's exact retained process identity.
        if state_file.exists() and read_json(state_file)['phase'] != 'unpaused':
            thaw(config, state_file)
        app = container(config, config['app'])
        db = container(config, config['database'])
        if app['State']['Status'] != 'running' or app['State']['Paused']:
            raise BackupError('instance_not_running')
        if db['State']['Status'] != 'running' or db['State']['Paused']:
            raise BackupError('database_not_running')
        if not any(m['Source'] == config['data'] and m['Destination'] == config['containerData']
                   for m in app['Mounts']):
            raise BackupError('data_binding')
        if app['Config'].get('User', '') not in ['', '0', 'root', '0:0']:
            raise BackupError('container_owner_changed')
        with urllib.request.urlopen(config['health'], timeout=1) as response:
            health = json.load(response)
        if health.get('status') != 'ok' or any(health['jobs']['counts'].values()):
            raise BackupError('instance_busy')
        quiescent(config)
        files = {}
        for name in config['files']:
            relative = pathlib.PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts:
                raise BackupError('config_path')
            path = pathlib.Path(config['directory']) / relative
            if path.is_symlink() or not path.is_file() or path.stat().st_size > 1048576:
                raise BackupError('config_file')
            files[name] = path.read_bytes()
        # Prove that the saved settings still contain the actual DB password.
        env_values = []
        for line in files['.env'].decode().splitlines():
            if not line.strip() or line.lstrip().startswith('#') or '=' not in line:
                continue
            value = line.split('=', 1)[1].strip()
            parsed = shlex.split(value)
            env_values.append(parsed[0] if len(parsed) == 1 else value)
        database_env = dict(value.split('=', 1) for value in db['Config']['Env'] if '=' in value)
        if not database_env.get('POSTGRES_PASSWORD') or database_env['POSTGRES_PASSWORD'] not in env_values:
            raise BackupError('database_settings_mismatch')
        pending = root / 'pending'
        if pending.is_symlink():
            raise BackupError('bundle_symlink')
        if pending.exists():
            shutil.rmtree(pending)
        pending.mkdir(mode=0o700)
        state = {'schemaVersion': 1, 'phase': 'armed', 'invocation': invocation,
                 'cid': app['Id'], 'image': app['Image'], 'identity': identity(app['State']['Pid']),
                 'pauseRequested': True}
        assert_identity(state)
        write_json(state_file, state)
        deadline = time.monotonic() + config['copySeconds']
        try:
            podman(config, 'pause', app['Id'])
            state['phase'] = 'paused'
            write_json(state_file, state)
            if not container(config, app['Id'])['State']['Paused']:
                raise BackupError('pause_not_observed')
            quiescent(config)
            if container(config, app['Id'])['Id'] != app['Id']:
                raise BackupError('container_identity')
            for name, value in files.items():
                if (pathlib.Path(config['directory']) / name).read_bytes() != value:
                    raise BackupError('config_changed')
                target = pending / name
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with target.open('xb') as out:
                    out.write(value)
                    out.flush()
                    os.fsync(out.fileno())
            expected_files, expected_logs = 0, 0
            for directory, directories, names in os.walk(config['data']):
                for name in names:
                    path = pathlib.Path(directory) / name
                    if path.is_symlink() or not path.is_file():
                        continue
                    if path.stat().st_uid != config['uid']:
                        raise BackupError('profile_owner_changed')
                    expected_files += 1
                    expected_logs += name.endswith('.log')
            remaining = max(.001, deadline - time.monotonic())
            snapshot(pending / 'database.dump', config['pg'],
                     max_bytes=min(config['maxBundleBytes'], 536870912), timeout_seconds=remaining)
            used = sum(len(value) for value in files.values()) + (pending / 'database.dump').stat().st_size
            with (pending / 'browser-data.tar').open('xb') as out:
                tar = stream_port([config['tar'], '--sort=name', '--format=pax',
                    '--pax-option=delete=atime,delete=ctime', '--numeric-owner', '--owner=0', '--group=0',
                    '-C', config['data'], '-cf', '-', '.'], out, deadline, config['maxBundleBytes'] - used)
                out.flush()
                os.fsync(out.fileno())
        finally:
            thaw(config, state_file)
        # Main is already thawed before any final publication work.
        manifest = {'schemaVersion': 1, 'invocation': invocation, 'appImage': app['Image'],
                    'databaseImage': db['Image'], 'containerOwner': {'uid': 0, 'gid': 0},
                    'browserArchive': tar, 'files': {}}
        for name in config['files'] + ['database.dump']:
            path = pending / name
            manifest['files'][name] = {'bytes': path.stat().st_size,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        with tarfile.open(pending / 'browser-data.tar', 'r:') as archive:
            members = archive.getmembers()
            if any(pathlib.PurePosixPath(member.name).is_absolute()
                   or '..' in pathlib.PurePosixPath(member.name).parts for member in members):
                raise BackupError('archive_path')
            manifest['entries'] = len(members)
            manifest['logEntries'] = sum(member.isfile() and member.name.endswith('.log') for member in members)
            if sum(member.isfile() for member in members) != expected_files or manifest['logEntries'] != expected_logs:
                raise BackupError('profile_entry_coverage')
        write_json(pending / 'manifest.json', manifest)
        publish(root)
        return manifest

def main(config_path, arguments):
    config = read_json(config_path)
    if arguments not in [['bundle'], ['thaw']]:
        raise BackupError('invalid_action')
    root = pathlib.Path(config['destination'])
    runtime = pathlib.Path(config['runtime'])
    if not runtime.is_dir() or runtime.is_symlink():
        raise BackupError('runtime_directory')
    state_file = runtime / 'state.json'
    if arguments == ['thaw']:
        thaw(config, state_file)
    else:
        invocation = os.environ.get('INVOCATION_ID')
        if not invocation:
            raise BackupError('unit_invocation_required')
        manifest = create_bundle(config, root, state_file, invocation)
        print(json.dumps({'code': 'snapshot_complete', 'entries': manifest['entries'],
                          'logEntries': manifest['logEntries'],
                          'browserBytes': manifest['browserArchive']['bytes']}))
