#!@python@
"""Managed headless Sunshine session, preserving the existing private streaming state.

Pairing, emulator saves and BIOS sidecars are CRITICAL existing data.
Display/audio runtime state is REPLACEABLE and removed by systemd.
"""
import ctypes
import errno
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import selectors
import re
import signal
import socket
import struct
import subprocess
import sys
import time

BASE = Path('@state@')
RUNTIME = Path('@runtime@')
PCSX = '@pcsx@'
DOLPHIN = '@dolphin@'
CATALOG = Path('@catalog@')
XVFB = '@xvfb@'
PULSE = '@pulse@'
OPENBOX = '@openbox@'
SUN = '@sunshine@'


def stream_endpoint(config):
    values = {}
    for line in config.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    address = str(ipaddress.IPv4Address(values['bind_address']))
    port = int(values.get('port', '47989')) + 21
    if not 1 <= port <= 65535:
        raise RuntimeError('STREAM_PORT_INVALID')
    return address, port


def wait_for_address(address, timeout=60, clock=time.monotonic, pause=time.sleep):
    # Bounded local prerequisite wait, not a retry of the streaming effect.
    deadline = clock() + timeout
    while True:
        with socket.socket() as probe:
            try:
                probe.bind((address, 0))
                return
            except OSError as error:
                if error.errno != errno.EADDRNOTAVAIL:
                    raise
        if clock() >= deadline:
            raise RuntimeError('STREAM_ADDRESS_TIMEOUT')
        pause(min(0.25, max(0, deadline - clock())))


def wait_for_listener(address, port, children, timeout=15,
                      clock=time.monotonic, pause=time.sleep):
    deadline = clock() + timeout
    while True:
        if any(child.poll() is not None for child in children):
            raise RuntimeError('STREAM_CHILD_EXITED')
        try:
            with socket.create_connection((address, port), timeout=0.25):
                return
        except OSError:
            if clock() >= deadline:
                raise RuntimeError('STREAM_LISTENER_TIMEOUT')
            pause(min(0.25, max(0, deadline - clock())))


def notify_ready(endpoint):
    if endpoint:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notification:
            notification.connect('\0' + endpoint[1:] if endpoint.startswith('@') else endpoint)
            notification.sendall(b'READY=1\nSTATUS=Streaming listener ready')



def catalog():
    data = json.loads(CATALOG.read_text())
    if data.get('schemaVersion') != 1 or not isinstance(data.get('games'), list):
        raise RuntimeError('GAME_CATALOG_VERSION_UNSUPPORTED')
    root = Path(data['roms']).resolve()
    games = {}
    for entry in data['games']:
        game_id = entry['id']
        rom = (root / entry['rom']).resolve()
        if (not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', game_id)
                or game_id in games or not rom.is_relative_to(root)
                or entry['system'] not in ['ps2', 'gamecube']):
            raise RuntimeError('GAME_CATALOG_INVALID_ENTRY')
        games[game_id] = dict(entry, path=rom)
    return games


def prepare_controllers():
    # CSimpleIni stores multiple bindings as repeated keys, not comma lists.
    # Preserve every existing keyboard/custom binding; add SDL controller input.
    ini = BASE / 'emulator-config/PCSX2/inis/PCSX2.ini'
    text = ini.read_text()
    marker = '; HWC Moonlight gamepad bindings v1'
    # Emulator saves may discard comments; binding presence is the stable marker.
    if not re.search(r'^Cross\s*=\s*SDL-0/FaceSouth\s*$', text, re.M):
        backup = ini.with_suffix('.ini.before-moonlight-gamepads')
        if not backup.exists():
            backup.write_bytes(ini.read_bytes()); backup.chmod(0o600)
        mappings = {
            'Cross': 'FaceSouth', 'Circle': 'FaceEast', 'Square': 'FaceWest',
            'Triangle': 'FaceNorth', 'Select': 'Back', 'Start': 'Start',
            'L1': 'LeftShoulder', 'R1': 'RightShoulder',
            'L2': '+LeftTrigger', 'R2': '+RightTrigger',
            'L3': 'LeftStick', 'R3': 'RightStick',
            'Up': 'DPadUp', 'Down': 'DPadDown', 'Left': 'DPadLeft', 'Right': 'DPadRight',
            'LUp': '-LeftY', 'LDown': '+LeftY', 'LLeft': '-LeftX', 'LRight': '+LeftX',
            'RUp': '-RightY', 'RDown': '+RightY', 'RLeft': '-RightX', 'RRight': '+RightX',
        }
        for player in [1, 2]:
            pattern = rf'(\[Pad{player}\]\n)(.*?)(?=\n\[|\Z)'
            def append(match):
                body = match[2]
                if player == 2:
                    body = re.sub(r'^Type\s*=\s*None\s*$', 'Type = DualShock2', body, flags=re.M)
                lines = [f'{key} = SDL-{player-1}/{value}' for key, value in mappings.items()]
                return match[1] + body.rstrip() + '\n' + marker + '\n' + '\n'.join(lines) + '\n'
            text, count = re.subn(pattern, append, text, flags=re.S)
            if count != 1:
                raise RuntimeError('PCSX2_PAD_SECTION_MISSING')
        temp = ini.with_suffix('.ini.tmp')
        temp.write_text(text); temp.chmod(0o600); temp.replace(ini)

    # New Dolphin saves are CRITICAL and retained in this private user directory.
    config = BASE / 'dolphin/Config'
    config.mkdir(parents=True, exist_ok=True)
    pad = config / 'GCPadNew.ini'
    if not pad.exists():
        mappings = {
            'Buttons/A': 'Button A', 'Buttons/B': 'Button B',
            'Buttons/X': 'Button X', 'Buttons/Y': 'Button Y',
            'Buttons/Z': 'Shoulder R', 'Buttons/Start': 'Start',
            'Main Stick/Up': 'Left Y+', 'Main Stick/Down': 'Left Y-',
            'Main Stick/Left': 'Left X-', 'Main Stick/Right': 'Left X+',
            'C-Stick/Up': 'Right Y+', 'C-Stick/Down': 'Right Y-',
            'C-Stick/Left': 'Right X-', 'C-Stick/Right': 'Right X+',
            'Triggers/L': 'Trigger L', 'Triggers/R': 'Trigger R',
            'Triggers/L-Analog': 'Trigger L', 'Triggers/R-Analog': 'Trigger R',
            'D-Pad/Up': 'Pad N', 'D-Pad/Down': 'Pad S',
            'D-Pad/Left': 'Pad W', 'D-Pad/Right': 'Pad E',
        }
        sections = []
        for player in range(4):
            sections += [f'[GCPad{player+1}]', f'Device = SDL/{player}/Xbox 360 Controller']
            sections += [f'{key} = `{value}`' for key, value in mappings.items()]
        pad.write_text('\n'.join(sections) + '\n'); pad.chmod(0o600)


def playable_image(entry):
    source = entry['path']
    if source.suffix.lower() != '.nrg':
        return source
    # Convert the supported single-track, 2048-byte Nero DAOX layout only.
    # Original media is read-only. REPLACEABLE cache: one ISO + manifest per
    # configured NRG, with at most one temporary replacement of each.
    with source.open('rb') as f:
        f.seek(-12, 2); tail = f.read(12)
        if tail[:4] != b'NER5':
            raise RuntimeError('NRG_FORMAT_UNSUPPORTED')
        footer = int.from_bytes(tail[4:], 'big'); f.seek(footer)
        for _ in range(64):
            header = f.read(8)
            if len(header) != 8:
                raise RuntimeError('NRG_DAOX_MISSING')
            size = int.from_bytes(header[4:], 'big')
            if size > 65536:
                raise RuntimeError('NRG_CHUNK_TOO_LARGE')
            data = f.read(size)
            if header[:4] == b'DAOX':
                break
        else:
            raise RuntimeError('NRG_DAOX_MISSING')
        if len(data) != 64 or data[20:22] != b'\x01\x01' or data[34:36] != b'\x08\x00':
            raise RuntimeError('NRG_TRACK_LAYOUT_UNSUPPORTED')
        start, end = struct.unpack('>QQ', data[-16:])
        f.seek(start + 16 * 2048); pvd = f.read(2048)
        length = int.from_bytes(pvd[80:84], 'little') * 2048
        if pvd[:6] != b'\x01CD001' or not 0 < start < end <= footer or start + length > end:
            raise RuntimeError('NRG_ISO_VOLUME_INVALID')
        f.seek(0); digest = hashlib.file_digest(f, 'sha256').hexdigest()
        expected = {'schemaVersion': 1, 'sourceSHA256': digest, 'offset': start, 'length': length}
        cache = BASE / 'disc-cache'; cache.mkdir(exist_ok=True)
        target = cache / (entry['id'] + '.iso'); meta = target.with_suffix('.json')
        if target.exists() and target.stat().st_size == length and meta.exists():
            try:
                if json.loads(meta.read_text()) == expected:
                    return target
            except (OSError, ValueError):
                pass  # REPLACEABLE metadata is rebuilt from the original image.
        temp = target.with_suffix('.iso.tmp')
        f.seek(start)
        with temp.open('wb') as output:
            remaining = length
            while remaining:
                block = f.read(min(8 * 1024 * 1024, remaining))
                if not block:
                    raise RuntimeError('NRG_TRUNCATED')
                output.write(block); remaining -= len(block)
            output.flush(); os.fsync(output.fileno())
        temp.replace(target)
        temp_meta = meta.with_suffix('.json.tmp')
        temp_meta.write_text(json.dumps(expected)); temp_meta.replace(meta)
        return target


def game_process(args, env, game_id, runtime=RUNTIME):
    # Foreground ownership lets Sunshine stop the emulator on disconnect.
    # AUTO-MANAGED log: last 64 KiB per configured game; discard oldest at limit.
    log = runtime / (game_id + '.log')
    child = subprocess.Popen(args, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, start_new_session=True)
    def stop(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    buffer = bytearray()
    poller = selectors.DefaultSelector(); poller.register(child.stdout, selectors.EVENT_READ)
    try:
        while True:
            if poller.select(timeout=0.25):
                chunk = os.read(child.stdout.fileno(), 8192)
                if not chunk:
                    break
                buffer.extend(chunk); del buffer[:-65536]
                log.write_bytes(buffer)
            elif child.poll() is not None:
                break
        return child.wait()
    except KeyboardInterrupt:
        return 0
    finally:
        poller.close(); child.stdout.close()
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=8)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL); child.wait(timeout=2)


def run():
    for required in ['credentials.json', 'server-key.pem', 'server-cert.pem']:
        if not (BASE / required).is_file():
            raise RuntimeError('Pilot preparation is incomplete: ' + required)
    address, port = stream_endpoint(Path(sys.argv[2]))
    wait_for_address(address)
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    for entry in catalog().values():
        if not entry['path'].is_file():
            raise RuntimeError('GAME_IMAGE_MISSING: ' + entry['id'])
    prepare_controllers()
    if Path('/tmp/.X11-unix/X95').exists():
        raise RuntimeError('Display :95 already exists; refusing to reuse it')
    auth = RUNTIME/'Xauthority'
    fields = [b'',b'95',b'MIT-MAGIC-COOKIE-1',os.urandom(16)]
    auth.write_bytes(struct.pack('>H',65535)+b''.join(struct.pack('>H',len(v))+v for v in fields))
    auth.chmod(0o600)
    env = dict(os.environ, DISPLAY=':95', XAUTHORITY=str(auth), XDG_RUNTIME_DIR='/run/user/1000',
               PULSE_SERVER='unix:' + str(RUNTIME/'pulse.socket'),
               QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion',
               LD_LIBRARY_PATH='/run/opengl-driver/lib')
    children=[]
    def stop(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        children.append(subprocess.Popen([XVFB,':95','-screen','0','1280x720x24',
            '-nolisten','tcp','-auth',str(auth)],env=env))
        children.append(subprocess.Popen([PULSE,'--daemonize=no','--exit-idle-time=-1',
            '--use-pid-file=no','-n',
            '--load=module-native-protocol-unix socket=' + str(RUNTIME/'pulse.socket') + ' auth-anonymous=1',
            '--load=module-null-sink sink_name=katamari_stream rate=48000 channels=2'],env=env))
        for _ in range(50):
            if any(p.poll() is not None for p in children):
                raise RuntimeError('Display or audio process failed')
            if Path('/tmp/.X11-unix/X95').exists() and (RUNTIME/'pulse.socket').exists():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError('Display/audio initialization timed out')
        children.append(subprocess.Popen([OPENBOX,'--sm-disable'],env=env))
        children.append(subprocess.Popen([SUN,sys.argv[2]],env=env))
        for _ in range(50):
            names={p.read_text().strip() for p in Path('/sys/class/input').glob('event*/device/name')}
            if {'Keyboard passthrough','Mouse passthrough'} <= names:
                break
            if any(p.poll() is not None for p in children):
                raise RuntimeError('A pilot dependency failed before input initialization')
            time.sleep(0.1)
        else:
            raise RuntimeError('Virtual input initialization timed out')
        children.append(subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'input'],env=env))
        wait_for_listener(address, port, children)
        notify_ready(os.environ.get('NOTIFY_SOCKET'))
        while all(p.poll() is None for p in children):
            time.sleep(0.5)
        raise RuntimeError('A pilot process exited; stopping the session')
    except KeyboardInterrupt:
        pass
    finally:
        for p in reversed(children):
            if p.poll() is None:
                p.terminate()
        deadline=time.monotonic()+8
        for p in reversed(children):
            try:
                p.wait(timeout=max(0.1,deadline-time.monotonic()))
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=2)


def game(runtime=RUNTIME):
    # Keyed before media/cache/config effects: one emulator owns shared saves.
    # Permanent by design; kernel flock releases on process exit, even after a crash.
    with (BASE / 'game.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('GAME_BUSY: close the current game before starting another.', file=sys.stderr)
            return 2
        return launch_game(runtime)


def launch_game(runtime):
    games = catalog()
    game_id = sys.argv[2] if len(sys.argv) > 2 else next(iter(games))
    if game_id not in games:
        raise RuntimeError('GAME_NOT_FOUND: ' + game_id)
    entry = games[game_id]
    image = playable_image(entry)
    env = dict(os.environ, XDG_CONFIG_HOME=str(BASE/'emulator-config'),
               QT_QPA_PLATFORM='xcb',QT_QPA_PLATFORMTHEME='generic',QT_STYLE_OVERRIDE='Fusion')
    if entry['system'] == 'gamecube':
        # Dolphin's native M3U boot path registers both discs for automatic
        # switching. Keep the requested disc first, including Disc 2 launchers.
        with image.open('rb') as source:
            game_code = source.read(6)
        discs = [image]
        for other in games.values():
            if other['system'] == 'gamecube' and other['path'] != image:
                with other['path'].open('rb') as source:
                    if source.read(6) == game_code:
                        discs.append(other['path'])
        if len(discs) > 1:
            playlist = runtime / (game_id + '.m3u')
            playlist.write_text(''.join(str(path) + '\n' for path in discs))
            image = playlist
        args = [DOLPHIN, '--batch', '--user=' + str(BASE/'dolphin'),
                '--video_backend=Vulkan', '-C', 'Dolphin.Display.Fullscreen=True',
                '-C', 'Dolphin.Interface.ConfirmStop=False',
                '-C', 'Dolphin.Core.AutoDiscChange=True',
                '-C', 'Logger.Options.WriteToConsole=True',
                '-C', 'Logger.Logs.BOOT=True', '-C', 'Logger.Logs.CORE=True']
        for port in range(4):
            args += ['-C', f'Dolphin.Core.SIDevice{port}=6']
        return game_process(args + ['--exec=' + str(image)], env, game_id, runtime)
    args=[PCSX,'-nogui','-fullscreen','-fastboot']
    marker=BASE/'resume-state'
    # The legacy one-launch marker belongs only to the original Katamari game.
    if game_id == next(iter(games)) and marker.exists():
        state=Path(marker.read_text().strip())
        if not state.is_file() or state.parent.resolve()!=(BASE/'savestates').resolve():
            raise RuntimeError('Invalid pilot resume state')
        args.extend(['-statefile',str(state)])
        marker.unlink()  # One launch only; preserve the state file itself.
    return game_process(args+['--',str(image)],env,game_id,runtime)


def input_bridge():
    # Permanent by design: Xvfb lacks evdev input; forward only Sunshine's named virtual devices.
    paths = {}
    for candidate in Path('/sys/class/input').glob('event*/device/name'):
        name=candidate.read_text().strip()
        device=candidate.parent
        if name in ['Keyboard passthrough','Mouse passthrough'] and (device/'id/vendor').read_text().strip()=='beef' and (device/'id/product').read_text().strip()=='dead':
            if name in paths:
                raise RuntimeError('Ambiguous virtual input devices')
            paths[name]=Path('/dev/input')/device.parent.name
    if len(paths)!=2:
        raise RuntimeError('Expected Sunshine keyboard and relative mouse devices')
    x=ctypes.CDLL('@libx11@/lib/libX11.so.6')
    t=ctypes.CDLL('@libxtst@/lib/libXtst.so.6')
    x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ctypes.c_void_p
    x.XFlush.argtypes=[ctypes.c_void_p];x.XCloseDisplay.argtypes=[ctypes.c_void_p]
    for function in [t.XTestFakeKeyEvent,t.XTestFakeButtonEvent]:
        function.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]
    t.XTestFakeRelativeMotionEvent.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_ulong]
    display=x.XOpenDisplay(b':95')
    if not display:
        raise RuntimeError('Cannot open pilot display')
    event=struct.Struct('llHHi')
    selector=selectors.DefaultSelector();fds=[];pressed=set()
    def stop(signum,frame):raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,stop)
    signal.signal(signal.SIGINT,stop)
    try:
        for name,path in paths.items():
            fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK);fds.append(fd);selector.register(fd,selectors.EVENT_READ,name)
        print('Sunshine virtual input connected to the pilot display',flush=True)
        while True:
            for key,_ in selector.select(timeout=1):
                data=os.read(key.fd,event.size*64)
                if not data or len(data)%event.size:
                    raise RuntimeError('Virtual input stream closed or malformed')
                for _,_,kind,code,value in event.iter_unpack(data):
                    if kind==1 and code<256 and key.data=='Keyboard passthrough' and value in [0,1]:
                        t.XTestFakeKeyEvent(display,code+8,value,0)
                        if value:pressed.add(code+8)
                        else:pressed.discard(code+8)
                    elif kind==1 and 272<=code<=274 and value in [0,1]:
                        t.XTestFakeButtonEvent(display,{272:1,273:3,274:2}[code],value,0)
                    elif kind==2 and code in [0,1]:
                        t.XTestFakeRelativeMotionEvent(display,value if code==0 else 0,value if code==1 else 0,0)
                    elif kind==2 and code==8:
                        for _ in range(min(abs(value),20)):
                            button=4 if value>0 else 5
                            t.XTestFakeButtonEvent(display,button,1,0);t.XTestFakeButtonEvent(display,button,0,0)
                x.XFlush(display)
    except KeyboardInterrupt:
        pass
    finally:
        for code in pressed:t.XTestFakeKeyEvent(display,code,0,0)
        x.XFlush(display);x.XCloseDisplay(display)
        selector.close()
        for fd in fds:os.close(fd)


if __name__ == '__main__':
    commands = {'run': run, 'game': game, 'input': input_bridge,
                'local-game': lambda: game(Path('@tvRuntime@'))}
    raise SystemExit(commands[sys.argv[1]]())
