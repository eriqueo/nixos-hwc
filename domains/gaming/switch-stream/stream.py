#!/usr/bin/env python3
"""Configuration payload for the Nix host and native Batocera client.

index.nix owns dependencies and options; this sibling owns executable setup.
All mutations are idempotent replacements or protected by nonblocking flock.
Private emulator data and pairing records never enter generated configuration.
"""
import ast
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import subprocess
import sys
import tarfile
import time

GUID = '030000007e0500000920000011810000'  # Eden normalizes SDL's GUID CRC bytes.
FACTORY_AGENT_SHA = '0535b9c7c6c56890d22490fcc0af9c54a82922af4713ef04cdb9e93ac0eb3a12'
PI_BASE = Path('/userdata/system/configs/switch-stream')
MOONLIGHT = Path('/userdata/system/.config/Moonlight Game Streaming Project/Moonlight.conf')
PREFS = {'gamepadmouse': 'false', 'swapfacebuttons': 'true'}
STREAM_OPTIONS = ['--720', '--fps', '60', '--bitrate', '10000', '--video-codec', 'HEVC', '--no-quit-after']


def call(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True,
                          capture_output=True, timeout=kwargs.pop('timeout', 15), **kwargs).stdout.strip()


def atomic(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.exists() and path.read_bytes() == data:
        path.chmod(mode)
        return False
    temp = path.with_name(path.name + '.new')
    with temp.open('wb') as output:
        os.fchmod(output.fileno(), mode)
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    temp.replace(path)
    return True


def merged_ini(text, updates):
    """Retain Qt escapes, ordering, comments and every unowned key verbatim."""
    pending = {s: dict(keys) for s, keys in updates.items()}
    result, section = [], None
    def finish():
        if section in pending:
            result.extend(f'{k}={v}\n' for k, v in pending.pop(section).items())
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            finish()
            section = stripped[1:-1]
        elif '=' in line and not stripped.startswith(('#', ';')):
            key = line.split('=', 1)[0].strip()
            if key in updates.get(section, {}):
                if key in pending.get(section, {}):
                    result.append(f'{key}={pending[section].pop(key)}\n')
                continue
        result.append(line if line.endswith('\n') else line + '\n')
    finish()
    for name, keys in pending.items():
        result += [f'\n[{name}]\n'] + [f'{k}={v}\n' for k, v in keys.items()]
    return ''.join(result)


def merge_file(path, updates, may_change=True):
    original = path.read_text() if path.exists() else ''
    changed = merged_ini(original, updates)
    if original == changed:
        return
    if not may_change:
        raise RuntimeError('CONFIG_BUSY: close the application before changing its settings')
    backup = path.with_name(path.name + '.before-switch-stream')
    if path.exists() and not backup.exists():
        atomic(backup, original.encode())
    atomic(path, changed.encode())


def controller_settings():
    buttons = dict(a=1, b=0, x=2, y=3, lstick=12, rstick=13, l=5, r=6,
                   zl=7, zr=8, plus=10, minus=9, home=11, screenshot=4,
                   slleft=5, srleft=6, slright=5, srright=6)
    bindings = {f'button_{key}': f'button:{value}' for key, value in buttons.items()}
    bindings.update({f'button_d{direction}': f'hat:0,direction:{direction}'
                     for direction in ['up', 'down', 'left', 'right']})
    for stick, x, y in [('lstick', 0, 1), ('rstick', 2, 3)]:
        bindings[stick] = (f'axis_x:{x},axis_y:{y},offset_x:0,offset_y:0,'
                           'invert_x:+,invert_y:+,deadzone:0.150000')
    values = {}
    # Handheld is slot 8. Slot 0 still receives the native meta shortcuts.
    for player in [0, 8]:
        values[f'player_{player}_connected'] = 'true' if player == 8 else 'false'
        values[f'player_{player}_type'] = '4'
        for key, value in bindings.items():
            values[f'player_{player}_{key}'] = f'"engine:sdl,port:0,guid:{GUID},{value}"'
    return {key: value for k, v in values.items() for key, value in [(k, v), (k + '\\default', 'false')]}


def eden_running():
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            if proc.stat().st_uid == os.getuid() and (proc / 'exe').resolve().name in ['eden', '.eden-wrapped']:
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def prepare_eden(cfg):
    if eden_running():
        raise RuntimeError('EDEN_BUSY: keep the current game running; prepare settings on the next launch')
    path = Path(cfg['edenConfig'])
    ui = {'fullscreen': 'true'}
    for name, chord in [('Continue\\Pause%20Emulation', 'Home+Plus'), ('Stop%20Emulation', 'L+Plus+Minus')]:
        key = 'Shortcuts\\Main%20Window\\' + name + '\\Controller_KeySeq'
        ui[key] = chord
        ui[key + '\\default'] = 'false'
    # Preserve existing folders. Register this root once for controller library navigation.
    current = path.read_text() if path.exists() else ''
    import configparser
    parsed = configparser.ConfigParser(interpolation=None, strict=False)
    parsed.optionxform = str
    parsed.read_string(current)
    existing = dict(parsed['UI']) if parsed.has_section('UI') else {}
    if cfg['gameRoot'] not in [v for k, v in existing.items() if k.startswith('Paths\\gamedirs\\') and k.endswith('\\path')]:
        size = int(existing.get('Paths\\gamedirs\\size', '0')) + 1
        prefix = f'Paths\\gamedirs\\{size}\\'
        ui.update({'Paths\\gamedirs\\size': str(size), prefix + 'path': cfg['gameRoot'],
                   prefix + 'deep_scan': 'true', prefix + 'deep_scan\\default': 'false'})
    merge_file(path, {
        'Controls': controller_settings(),
        'System': {'use_docked_mode': '0', 'use_docked_mode\\default': 'false'},
        'Renderer': {'backend': '1', 'backend\\default': 'false'},
        'UI': ui,
    })


def migrate(cfg, source):
    state = Path(cfg['state']); state.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Reserve the migration before any private file effect; never replace an identity.
    with (state / 'setup.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        files = ['state.json', 'key.pem', 'cert.pem']
        for name in files:
            incoming, target = source / name, state / name
            if not incoming.is_file():
                raise RuntimeError('PAIRING_SOURCE_MISSING: ' + name)
            if target.exists() and incoming.read_bytes() != target.read_bytes():
                raise RuntimeError('PAIRING_IDENTITY_CONFLICT: ' + name)
        for name in files + ['credentials.json']:
            if (source / name).is_file():
                atomic(state / name, (source / name).read_bytes())
        print('Pairing copied and verified; source retained')


def wait_ready(probe, children=(), timeout=60):
    # Read-only readiness polling is bounded. Exhaustion fails visibly.
    deadline = time.monotonic() + timeout
    while True:
        if any(p.poll() is not None for p in children):
            raise RuntimeError('STREAM_CHILD_EXITED')
        try:
            if probe():
                return
        except (OSError, subprocess.SubprocessError):
            pass
        if time.monotonic() >= deadline:
            raise RuntimeError('STREAM_PREREQUISITE_TIMEOUT')
        time.sleep(0.25)


def listener(host, port):
    with socket.create_connection((host, port), timeout=0.25):
        return True


def stop_children(children):
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
    deadline = time.monotonic() + 8
    for child in reversed(children):
        try:
            child.wait(timeout=max(0.1, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            child.kill(); child.wait(timeout=2)


def keep_library_focus(xdotool, window, wait):
    """Recover X11 logical focus after Eden destroys its game render window.

    Poll only during this emulator's lifetime. Preserve any valid focus,
    including text dialogs and other X11 apps; never activate a Hyprland window.
    """
    failed = False
    while True:
        try:
            return wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            try:
                focus = subprocess.run([xdotool, 'getwindowfocus'], capture_output=True, timeout=2)
                if focus.returncode == 0:
                    continue
                call([xdotool, 'windowfocus', window])
                failed = False
            except (OSError, subprocess.SubprocessError):
                # A focus failure must not terminate a game with unsaved progress.
                if not failed:
                    print('EDEN_FOCUS_UNAVAILABLE: library focus could not be restored', file=sys.stderr, flush=True)
                failed = True


def watch_focus(cfg, pid):
    """Attach the same focus recovery to an already-running trial, without restarting it."""
    proc = Path('/proc') / str(int(pid))
    if proc.stat().st_uid != os.getuid() or (proc / 'exe').resolve().name not in ['eden', '.eden-wrapped']:
        raise RuntimeError('EDEN_PROCESS_REQUIRED')
    started = (proc / 'stat').read_text().split(') ', 1)[1].split()[19]
    xdotool = cfg['binaries']['xdotool']
    windows = call([xdotool, 'search', '--name', '^eden [|]']).splitlines()
    if len(windows) != 1:
        raise RuntimeError('EDEN_WINDOW_AMBIGUOUS')
    def wait(timeout):
        time.sleep(timeout)
        try:
            if (proc / 'stat').read_text().split(') ', 1)[1].split()[19] != started:
                return 0
        except FileNotFoundError:
            return 0
        raise subprocess.TimeoutExpired('eden', timeout)
    print('Watching library focus until this Eden process exits', flush=True)
    return keep_library_focus(xdotool, windows[0], wait)


def host_run(cfg, sunshine_config):
    for name in ['state.json', 'key.pem', 'cert.pem']:
        if not (Path(cfg['state']) / name).is_file():
            raise RuntimeError('PAIRING_NOT_PREPARED: use migrate with a private Sunshine state directory')
    if eden_running() or subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'sunshine-pikachu-test']).returncode == 0:
        raise RuntimeError('TRIAL_ACTIVE: refusing to interrupt the existing game or listener')
    binaries = cfg['binaries']; hypr = binaries['hyprctl']
    wait_ready(lambda: bool(call([hypr, '-j', 'monitors'])))
    monitors = json.loads(call([hypr, '-j', 'monitors', 'all']))
    if cfg['monitor'] not in [m['name'] for m in monitors]:
        call([hypr, 'output', 'create', 'headless', cfg['monitor']])
    call([hypr, 'keyword', 'monitor', f"{cfg['monitor']},1920x1080@60,10000x0,1"])
    call([hypr, 'keyword', 'workspace', f"{cfg['workspace']},monitor:{cfg['monitor']},persistent:true"])
    call([hypr, 'dispatch', 'moveworkspacetomonitor', f"{cfg['workspace']} {cfg['monitor']}"])
    focused = next((m['name'] for m in monitors if m.get('focused')), None)
    call([hypr, 'dispatch', 'workspace', str(cfg['workspace'])])
    if focused:
        call([hypr, 'dispatch', 'focusmonitor', focused])
    for effects in [f"workspace {cfg['workspace']} silent", 'no_initial_focus on, suppress_event activate']:
        call([hypr, 'keyword', 'windowrule', f'match:class ^([Ee]den|dev[.]eden_emu[.]eden)$, {effects}'])
    runtime = Path(os.environ['XDG_RUNTIME_DIR']) / 'hwc-switch-stream'
    runtime.mkdir(exist_ok=True, mode=0o700)
    env = dict(os.environ, PULSE_SERVER='unix:' + str(runtime / 'pulse.socket'))
    children = []
    def stop(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    try:
        children.append(subprocess.Popen([binaries['pulse'], '--daemonize=no', '--exit-idle-time=-1',
            '--use-pid-file=no', '-n', '--load=module-native-protocol-unix socket=' + str(runtime / 'pulse.socket') + ' auth-anonymous=1',
            '--load=module-null-sink sink_name=hwc_switch_stream rate=48000 channels=2'], env=env))
        wait_ready(lambda: (runtime / 'pulse.socket').exists(), children, timeout=10)
        children.append(subprocess.Popen([binaries['sunshine'], sunshine_config], env=env))
        wait_ready(lambda: listener(cfg['host'], 48010), children, timeout=45)
        endpoint = os.environ.get('NOTIFY_SOCKET')
        if endpoint:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notification:
                notification.connect('\0' + endpoint[1:] if endpoint.startswith('@') else endpoint)
                notification.sendall(b'READY=1\nSTATUS=Switch stream listener ready')
        while all(p.poll() is None for p in children):
            time.sleep(0.5)
        raise RuntimeError('STREAM_CHILD_EXITED')
    except KeyboardInterrupt:
        pass
    finally:
        stop_children(children)


def game(cfg, game_id):
    # Permanent by design: one emulator owns the shared saves at a time.
    with (Path(cfg['state']) / 'game.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        prepare_eden(cfg)
        args = [cfg['binaries']['eden']]
        if game_id != 'library':
            entry = next(g for g in cfg['games'] if g['id'] == game_id)
            root = Path(cfg['gameRoot']).resolve()
            image = (root / entry['file']).resolve()
            if not image.is_relative_to(root) or not image.is_file():
                raise RuntimeError('GAME_IMAGE_MISSING: ' + game_id)
            args += ['-g', str(image)]
        # Sunshine passes its private Pulse server environment to app children.
        child = subprocess.Popen(args)
        def stop(signum, frame):
            raise KeyboardInterrupt()
        signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
        try:
            # Qt's controller library navigation requires X11 logical focus.
            # windowfocus leaves Hyprland's physical desktop focus unchanged.
            window = []
            def find_window():
                found = call([cfg['binaries']['xdotool'], 'search', '--name', '^eden [|]'])
                window[:] = found.splitlines()
                return bool(window)
            wait_ready(find_window, [child], timeout=30)
            if len(window) != 1:
                raise RuntimeError('EDEN_WINDOW_AMBIGUOUS')
            call([cfg['binaries']['xdotool'], 'windowfocus', window[0]])
            return keep_library_focus(cfg['binaries']['xdotool'], window[0], child.wait)
        except KeyboardInterrupt:
            return 0
        finally:
            stop_children([child])


def patched_agent(source):
    tree = ast.parse(source)
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'refresh_audio_on_connect')
    guard = ast.parse('if not properties.get("Connected", False):\n  return\n').body[0]
    if ast.dump(function.body[0]) == ast.dump(guard):
        return source
    if hashlib.sha256(source.encode()).hexdigest() != FACTORY_AGENT_SHA:
        raise RuntimeError('BLUETOOTH_AGENT_UNSUPPORTED: inspect the new factory source before patching')
    lines = source.splitlines(keepends=True)
    lines.insert(function.lineno,
        '  # Temporary: ignore disconnected audio discovery; remove when the factory agent has this guard.\n'
        '  if not properties.get("Connected", False):\n    return\n')
    result = ''.join(lines); compile(result, '<bluetooth-agent>', 'exec')
    return result


def pi_start(cfg):
    with Path('/run/switch-stream.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return pi_start_locked(cfg)


def pi_start_locked(cfg):
    source = Path('/overlay/base/usr/bin/batocera-bluetooth-agent').read_text()
    agent = patched_agent(source).encode()  # Check upgrade compatibility before changing runtime state.
    os.environ.update(XDG_RUNTIME_DIR='/var/run', WAYLAND_DISPLAY='wayland-0', DISPLAY=':0')
    wait_ready(lambda: bool(call(['pactl', 'info'])), timeout=30)
    sinks = call(['pactl', 'list', 'short', 'sinks'])
    if not any(line.split()[1] == 'tv_hdmi' for line in sinks.splitlines() if len(line.split()) > 1):
        # Temporary HDMI PCM bridge: remove when the native profile exposes vc4hdmi0 PCM.
        # ALSA's hdmi plugin performs IEC958 conversion; raw hw:0,0 does not.
        call(['pactl', 'load-module', 'module-alsa-sink', 'device=hdmi:CARD=vc4hdmi0,DEV=0',
              'sink_name=tv_hdmi', 'channels=2', 'rate=48000'])
    call(['pactl', 'set-default-sink', 'tv_hdmi'])
    call(['pactl', 'set-sink-mute', 'tv_hdmi', '0'])
    wait_ready(lambda: 'HDMI-A-1' in call(['wlr-randr']), timeout=45)
    call(['wlr-randr', '--output', 'HDMI-A-1', '--mode', '1920x1080@60Hz'])
    call(['btmgmt', 'connectable', 'on'])
    if atomic(Path('/usr/bin/batocera-bluetooth-agent'), agent, 0o755):
        pid = '/var/run/bluetooth-agent.pid'
        call(['start-stop-daemon', '--stop', '--quiet', '--retry', 'TERM/5/KILL/1', '--pidfile', pid])
        call(['start-stop-daemon', '--start', '--quiet', '--background', '--make-pidfile', '--pidfile', pid,
              '--exec', '/usr/bin/batocera-bluetooth-agent'])
    return {'schemaVersion': 1, 'state': 'ready', 'audio': call(['pactl', 'get-default-sink']), 'display': '1920x1080@60'}


def pi_install(cfg, config_path):
    # Native Batocera services own boot; never replace custom.sh or other services.
    client = PI_BASE / 'stream.py'
    invoke = f'python3 {shlex.quote(str(client))} {shlex.quote(str(config_path))}'
    atomic(Path('/userdata/system/services/switch_stream'),
           f'#!/bin/sh\nexec {invoke} pi-service "$@"\n'.encode(), 0o755)
    for entry in cfg['games']:
        launcher = Path('/userdata/roms/ports') / f"Switch - {entry['id']}.sh"
        atomic(launcher, f'#!/bin/sh\nexec {invoke} pi-stream {shlex.quote(entry["id"])}\n'.encode(), 0o755)
    atomic(Path('/userdata/roms/ports/Switch - library.sh'),
           f'#!/bin/sh\nexec {invoke} pi-stream library\n'.encode(), 0o755)
    merge_file(MOONLIGHT, {'General': PREFS}, may_change=not moonlight_running())
    call(['batocera-services', 'enable', 'switch_stream'])


def moonlight_running():
    return subprocess.run(['pgrep', '-x', 'moonlight-qt'], capture_output=True).returncode == 0


def pi_stream(cfg, game_id):
    if moonlight_running():
        raise RuntimeError('MOONLIGHT_BUSY: close the current stream before launching another')
    pi_start(cfg)
    merge_file(MOONLIGHT, {'General': PREFS})
    title = 'Switch library' if game_id == 'library' else next(g['title'] for g in cfg['games'] if g['id'] == game_id)
    os.environ['SDL_VIDEODRIVER'] = 'wayland'
    os.execvp('moonlight-qt', ['moonlight-qt', 'stream', *STREAM_OPTIONS, cfg['host'], title])


def provision_pi(cfg, config_path):
    host = 'root@' + cfg['pi']
    ssh = ['ssh', '-o', 'BatchMode=yes', host]
    # Snapshot files before installation. No credential bytes are returned to chat.
    call(ssh + ['install -d -m 700 /userdata/system/configs/switch-stream'])
    for source, target in [(Path(__file__), PI_BASE / 'stream.py'), (config_path, PI_BASE / 'config.json')]:
        with source.open('rb') as data:
            call(ssh + ['umask 077; cat > ' + shlex.quote(str(target))], stdin=data, timeout=30)
    print(call(ssh + ['python3 /userdata/system/configs/switch-stream/stream.py '
                      '/userdata/system/configs/switch-stream/config.json pi-install'], timeout=30))


def backup(cfg):
    target = Path(cfg['backup'])
    mount = target.parent
    if not mount.is_mount():
        raise RuntimeError('BACKUP_MOUNT_MISSING')
    target.mkdir(mode=0o700, exist_ok=True)
    with (target / 'backup.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # AUTO-MANAGED snapshots: latest + previous, one staging file at most.
        staging = target / 'latest.tar.gz.new'
        staging.touch(mode=0o600)
        with tarfile.open(staging, 'w:gz') as archive:
            for source, name in [(Path(cfg['state']), 'sunshine'), (Path(cfg['edenConfig']).parent, 'eden-config'),
                                 (Path(cfg['edenData']) / 'keys', 'eden-keys'), (Path(cfg['edenData']) / 'nand/user', 'eden-saves')]:
                if source.exists():
                    archive.add(source, arcname=name)
        staging.chmod(0o600)
        pi_copy = target / 'pi-state.tar.gz.new'
        pi_copy.touch(mode=0o600)
        with pi_copy.open('wb') as output:
            subprocess.run(['ssh', '-o', 'BatchMode=yes', 'root@' + cfg['pi'],
                            'tar -czf - -C /userdata/system bluetooth .config/"Moonlight Game Streaming Project"'],
                           stdout=output, check=True, timeout=30)
        pi_copy.chmod(0o600)
        for source, name in [(staging, 'latest.tar.gz'), (pi_copy, 'pi-state.tar.gz')]:
            dest = target / name
            if dest.exists():
                dest.replace(target / ('previous-' + name))
            source.replace(dest)
        print('Private laptop and Pi state snapshots saved to ' + str(target))


def start(cfg):
    if eden_running():
        raise RuntimeError('EDEN_BUSY: save and close Eden before starting the managed session')
    # Explicit operator cutover only. Boot never stops another streaming service.
    if subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'sunshine-pikachu-test']).returncode == 0:
        call(['systemctl', '--user', 'stop', 'sunshine-pikachu-test'])
    (Path(os.environ['XDG_RUNTIME_DIR']) / 'hwc-switch-stream.defer').unlink(missing_ok=True)
    call(['systemctl', '--user', 'start', 'hwc-switch-stream'], timeout=100)


def main():
    os.umask(0o077)
    config_path = Path(sys.argv[1]); cfg = json.loads(config_path.read_text())
    if cfg.get('schemaVersion') != 1:
        raise RuntimeError('CONFIG_VERSION_UNSUPPORTED')
    command, *args = sys.argv[2:]
    commands = {
        'watch-focus': lambda: watch_focus(cfg, args[0]),
        'start': lambda: start(cfg),
        'migrate': lambda: migrate(cfg, Path(args[0])),
        'prepare': lambda: prepare_eden(cfg),
        'host-run': lambda: host_run(cfg, args[0]),
        'game': lambda: game(cfg, args[0]),
        'pi-install': lambda: pi_install(cfg, config_path),
        'pi-setup': lambda: provision_pi(cfg, config_path),
        'pi-stream': lambda: pi_stream(cfg, args[0]),
        'backup': lambda: backup(cfg),
    }
    if command == 'pi-service':
        if args == ['stop']:
            return 0  # No resident child; Bluetooth/PipeWire remain native-owned.
        if args not in [['start'], ['status']]:
            raise RuntimeError('COMMAND_INVALID')
        status = Path('/run/switch-stream-status.json')
        if args == ['status']:
            print(status.read_text()); return 0
        try:
            result = pi_start(cfg)
        except Exception:
            atomic(status, b'{"schemaVersion":1,"state":"failed"}\n')
            call(['logger', '-t', 'switch_stream', 'Startup failed; inspect /run/switch-stream-status.json'])
            raise
        atomic(status, json.dumps(result).encode())
        call(['logger', '-t', 'switch_stream', 'TV audio, 1080p display and Bluetooth are ready'])
        return 0
    if command not in commands:
        print('Commands: ' + ', '.join(commands), file=sys.stderr)
        return 2
    return commands[command]()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError, StopIteration) as error:
        print(str(error) or 'GAME_NOT_FOUND', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr[-4096:], file=sys.stderr)
        raise SystemExit(1)
