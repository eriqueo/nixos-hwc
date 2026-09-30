"""Check startup, exit and signal handling without opening a vault."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

LAUNCHER = Path(os.environ.get("BITWARDEN_PORTAL_TEST_LAUNCHER", Path(__file__).with_name("portal-launcher.py")))


class PortalLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ | {
            "XDG_RUNTIME_DIR": str(self.root),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/unused-fixture-bus",
        }

    def script(self, name, body):
        path = self.root / name
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o700)
        return str(path)

    def run_launcher(self, proxy, app, *args):
        return subprocess.run(
            [sys.executable, str(LAUNCHER), proxy, app, *args],
            env=self.env, capture_output=True, text=True, timeout=10,
        )

    def test_proxy_failure_refuses_to_launch_app(self):
        proxy = self.script("proxy", "raise SystemExit(42)\n")
        marker = self.root / "app-started"
        app = self.script("app", f"open({str(marker)!r}, 'w').close()\n")
        result = self.run_launcher(proxy, app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("BITWARDEN_PORTAL_STARTUP_FAILED", result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(list(self.root.glob("bitwarden-portal-*")), [])

    def test_app_exit_preserves_arguments_and_cleans_proxy(self):
        proxy_pid = self.root / "proxy-pid"
        proxy = self.script("proxy", f"""import os, sys, time
open({str(proxy_pid)!r}, 'w').write(str(os.getpid()))
fd = int(next(x[5:] for x in sys.argv if x.startswith('--fd=')))
os.write(fd, b'1')
time.sleep(30)
""")
        app = self.script("app", """import os, sys
assert sys.argv[1:] == ['--autostart', 'argument with spaces']
assert os.environ['DBUS_SESSION_BUS_ADDRESS'].endswith('/bus')
raise SystemExit(17)
""")
        result = self.run_launcher(proxy, app, "--autostart", "argument with spaces")
        self.assertEqual(result.returncode, 17, result.stderr)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(proxy_pid.read_text()), 0)
        self.assertEqual(list(self.root.glob("bitwarden-portal-*")), [])

    def test_readiness_deadline_refuses_to_launch(self):
        proxy = self.script("proxy", "import time\ntime.sleep(30)\n")
        app = self.script("app", "raise SystemExit(0)\n")
        start = time.monotonic()
        result = self.run_launcher(proxy, app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("BITWARDEN_PORTAL_STARTUP_FAILED", result.stderr)
        self.assertLess(time.monotonic() - start, 7)
        self.assertEqual(list(self.root.glob("bitwarden-portal-*")), [])

    def test_relay_exit_stops_client(self):
        app_pid = self.root / "app-pid"
        proxy = self.script("proxy", """import os, sys, time
os.write(int(next(x[5:] for x in sys.argv if x.startswith('--fd='))), b'1')
time.sleep(0.5)
""")
        app = self.script("app", f"""import os, time
open({str(app_pid)!r}, 'w').write(str(os.getpid()))
time.sleep(30)
""")
        result = self.run_launcher(proxy, app)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BITWARDEN_PORTAL_RELAY_EXITED", result.stderr)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(app_pid.read_text()), 0)
        self.assertEqual(list(self.root.glob("bitwarden-portal-*")), [])

    def test_sigterm_cleans_app_and_proxy(self):
        proxy_pid = self.root / "proxy-pid"
        app_pid = self.root / "app-pid"
        proxy = self.script("proxy", f"""import os, sys, time
open({str(proxy_pid)!r}, 'w').write(str(os.getpid()))
os.write(int(next(x[5:] for x in sys.argv if x.startswith('--fd='))), b'1')
time.sleep(30)
""")
        app = self.script("app", f"""import os, time
open({str(app_pid)!r}, 'w').write(str(os.getpid()))
time.sleep(30)
""")
        proc = subprocess.Popen([sys.executable, str(LAUNCHER), proxy, app], env=self.env)
        try:
            deadline = time.monotonic() + 5
            while not app_pid.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(app_pid.exists())
            proc.terminate()
            self.assertEqual(proc.wait(timeout=6), 143)
            for path in (proxy_pid, app_pid):
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(path.read_text()), 0)
            self.assertEqual(list(self.root.glob("bitwarden-portal-*")), [])
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()


if __name__ == "__main__":
    unittest.main()
