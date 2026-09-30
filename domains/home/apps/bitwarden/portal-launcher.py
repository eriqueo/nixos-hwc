"""Keep Bitwarden's session-bus relay alive only while the client runs.

Bitwarden's PR_SET_DUMPABLE=0 blocks portal caller identification via /proc.
The relay holds no vault state and leaves process isolation enabled. Remove
when a direct hardened-client FileChooser.OpenFile request succeeds upstream.
"""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile

READY_SECONDS = 5
STOP_SECONDS = 5


class Shutdown(Exception):
    def __init__(self, signum):
        self.signum = signum


def stop(child):
    if child is None or child.poll() is not None:
        return
    child.terminate()
    try:
        child.wait(timeout=STOP_SECONDS)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()


def run(proxy_exe, app_argv, runtime_dir, bus_address):
    """One relay per invocation; failure refuses launch, with no retries."""
    if not runtime_dir or not bus_address or not app_argv:
        print("BITWARDEN_PORTAL_CONFIG_INVALID: session bus and runtime directory required", file=sys.stderr)
        return 1
    runtime = Path(runtime_dir)
    if not runtime.is_dir() or runtime.stat().st_uid != os.getuid():
        print("BITWARDEN_PORTAL_CONFIG_INVALID: runtime directory must belong to this user", file=sys.stderr)
        return 1

    proxy = app = None
    previous = {}

    def interrupted(signum, _frame):
        raise Shutdown(signum)

    try:
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            previous[signum] = signal.signal(signum, interrupted)
        # AUTO-MANAGED runtime state: private socket, removed at client exit.
        with tempfile.TemporaryDirectory(prefix="bitwarden-portal-", dir=runtime) as temp:
            read_fd, write_fd = os.pipe()
            try:
                proxy = subprocess.Popen(
                    [proxy_exe, bus_address, temp + "/bus", "--fd=" + str(write_fd)],
                    pass_fds=(write_fd,),
                )
                os.close(write_fd)
                write_fd = None
                if not select.select([read_fd], [], [], READY_SECONDS)[0] or not os.read(read_fd, 1):
                    print("BITWARDEN_PORTAL_STARTUP_FAILED: relay did not become ready", file=sys.stderr)
                    return 1
                if proxy.poll() is not None:
                    print("BITWARDEN_PORTAL_STARTUP_FAILED: relay exited before launch", file=sys.stderr)
                    return 1
                env = os.environ | {"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + temp + "/bus"}
                app = subprocess.Popen(app_argv, env=env)
                while True:
                    try:
                        return app.wait(timeout=0.5)
                    except subprocess.TimeoutExpired:
                        if proxy.poll() is not None:
                            print("BITWARDEN_PORTAL_RELAY_EXITED: stopping client", file=sys.stderr)
                            return 1
            finally:
                os.close(read_fd)
                if write_fd is not None:
                    os.close(write_fd)
                # Drain children before unlinking their socket; no orphan daemon.
                for signum in previous:
                    signal.signal(signum, signal.SIG_IGN)
                stop(app)
                stop(proxy)
    except Shutdown as exc:
        return 128 + exc.signum
    except OSError as exc:
        print("BITWARDEN_PORTAL_STARTUP_FAILED:", exc.strerror, file=sys.stderr)
        return 1
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("BITWARDEN_PORTAL_CONFIG_INVALID: relay and client commands required")
    raise SystemExit(run(sys.argv[1], sys.argv[2:], os.environ.get("XDG_RUNTIME_DIR"), os.environ.get("DBUS_SESSION_BUS_ADDRESS")))
