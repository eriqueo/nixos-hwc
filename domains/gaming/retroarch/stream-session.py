#!@python@
"""Managed headless Sunshine session, preserving the existing private streaming state.

Pairing, emulator saves and BIOS sidecars are CRITICAL existing data.
Display/audio runtime state is REPLACEABLE and removed by systemd.
"""
import ctypes
import json
import os
from pathlib import Path
import selectors
import signal
import struct
import subprocess
import sys
import time

BASE = Path('@state@')
RUNTIME = Path('@runtime@')
PCSX = '@pcsx@'
XVFB = '@xvfb@'
PULSE = '@pulse@'
OPENBOX = '@openbox@'
GAME = '@game@'
SUN = '@sunshine@'



def run():
    for required in ['credentials.json', 'server-key.pem', 'server-cert.pem']:
        if not (BASE / required).is_file():
            raise RuntimeError('Pilot preparation is incomplete: ' + required)
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
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


def game():
    env = dict(os.environ, XDG_CONFIG_HOME=str(BASE/'emulator-config'),
               QT_QPA_PLATFORM='xcb',QT_QPA_PLATFORMTHEME='generic',QT_STYLE_OVERRIDE='Fusion')
    args=[PCSX,'-nogui','-fullscreen','-fastboot']
    marker=BASE/'resume-state'
    if marker.exists():
        state=Path(marker.read_text().strip())
        if not state.is_file() or state.parent.resolve()!=(BASE/'savestates').resolve():
            raise RuntimeError('Invalid pilot resume state')
        args.extend(['-statefile',str(state)])
        marker.unlink()  # One launch only; preserve the state file itself.
    os.execve(PCSX,args+['--',GAME],env)


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
    {'run':run,'game':game,'input':input_bridge}[sys.argv[1]]()
