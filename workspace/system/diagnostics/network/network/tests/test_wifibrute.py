"""Run the production script with fake tools; never probe a real network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "wifibrute.sh"
FAKE = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\n')
if name == 'sudo':
    if args == ['-v']: sys.exit(0)
    if args and args[0] == '-n': args = args[1:]
    os.execvp(args[0], args)
if name == 'ip':
    if 'default' in args:
        print('default via 192.168.0.1 dev wlan0')
    elif 'addr' in args:
        print('2: wlan0 inet 192.168.0.136/23 brd 192.168.1.255 scope global wlan0')
    sys.exit(0)
if name == 'airmon-ng':
    if args[0] == 'start':
        if os.environ.get('MON_FAIL'): sys.exit(1)
        Path(os.environ['MON_STATE']).touch()
        if os.environ.get('MON_PARTIAL'): sys.exit(1)
    else:
        Path(os.environ['MON_STATE']).unlink(missing_ok=True)
    sys.exit(0)
if name == 'iw':
    if args[1] == 'wlan0mon':
        if not Path(os.environ['MON_STATE']).exists(): sys.exit(1)
        print('type monitor')
    else:
        print('type managed')
    sys.exit(0)
if name == 'airodump-ng':
    sys.exit(2 if os.environ.get('CAPTURE_FAIL') else 0)
if name == 'suricata':
    print('fixture invalid IDS config', file=sys.stderr)
    sys.exit(3)
if name == 'arp-scan':
    if os.environ.get('ARP_FAIL'): sys.exit(1)
    print('192.168.0.1\taa:bb:cc:dd:ee:ff\tVendor')
    sys.exit(0)
if name == 'nmap':
    prefix = Path(args[args.index('-oA') + 1])
    if os.environ.get('FAIL_STAGE') == prefix.name:
        print('fixture scan failure', file=sys.stderr)
        sys.exit(3)
    hosts = '' if os.environ.get('EMPTY') else (
        'Host: 192.168.0.1 ()\tStatus: Up\n'
        'Host: 192.168.0.97 (hwc-home.local)\tStatus: Up\n'
        'Host: 192.168.0.136 (hwc-laptop.local)\tStatus: Up\n'
        'Host: 192.168.0.200 ()\tStatus: Down\n')
    prefix.with_suffix('.gnmap').write_text(hosts)
    prefix.with_suffix('.nmap').write_text(
        'Skipping host 192.168.0.97 due to host timeout\n'
        if os.environ.get('PARTIAL') and prefix.name == 'tcp-all' else '')
    prefix.with_suffix('.xml').write_text('<nmaprun/>')
'''


class AuditTests(unittest.TestCase):
    def run_audit(self, inputs="\nn\nn\nn\n", args=(), arp=False, radio=False, ids=False, entry=SCRIPT, **flags):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            # Isolated PATH prevents ambient radio/IDS tools and real sudo/nmap.
            for tool in ("bash", "python3", "awk", "sort", "tr", "wc", "head",
                         "cut", "date", "mkdir", "mktemp", "timeout", "tee", "rg",
                         "grep", "sed", "cat", "dirname", "sleep", "kill", "ls"):
                found = shutil.which(tool)
                if found:
                    (bin_dir / tool).symlink_to(found)
            for tool in ("sudo", "ip", "nmap", *(("arp-scan",) if arp else ()),
                         *(("airmon-ng", "iw", "airodump-ng") if radio else ()),
                         *(("suricata",) if ids else ())):
                p = bin_dir / tool
                p.write_text(FAKE)
                p.chmod(0o755)
            calls = root / "calls"
            env = {**os.environ, "PATH": str(bin_dir), "CALLS": str(calls),
                   "MON_STATE": str(root / "monitor"), **flags}
            result = subprocess.run(["bash", str(entry), *args], input=inputs,
                                    text=True, capture_output=True, cwd=root,
                                    env=env, timeout=10)
            reports = list((root / "reports").glob("*"))
            files = {f.name: f.read_text() for report in reports
                     for f in report.iterdir() if f.is_file()}
            if reports:
                files["directory-mode"] = oct(reports[0].stat().st_mode & 0o777)
            commands = [json.loads(line) for line in calls.read_text().splitlines()]
            return result, files, commands

    def test_nmap_inventory(self):
        result, files, _ = self.run_audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(files["live-hosts.txt"].splitlines(),
                         ["192.168.0.1", "192.168.0.136", "192.168.0.97"])
        self.assertEqual(files["directory-mode"], "0o700")

    def test_discovery_only_uses_real_prefix(self):
        result, _, calls = self.run_audit(inputs="\n", args=("discover",))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scans = [c for c in calls if c[0] == "nmap"]
        self.assertEqual(len(scans), 1)
        self.assertIn("192.168.0.0/23", scans[0])
        self.assertIn("-sn", scans[0])

    def test_custom_remote_target_does_not_use_arp(self):
        result, _, calls = self.run_audit(inputs="10.0.0.14/28\n", args=("discover",), arp=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(c[0] == "arp-scan" for c in calls))
        self.assertIn("10.0.0.0/28", next(c for c in calls if c[0] == "nmap"))

    def test_local_arp_honors_target(self):
        result, _, calls = self.run_audit(inputs="192.168.0.0/28\n", args=("discover",), arp=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scan = next(c for c in calls if c[0] == "arp-scan")
        self.assertIn("192.168.0.0/28", scan)
        self.assertNotIn("--localnet", scan)

    def test_arp_failure_falls_back(self):
        result, files, _ = self.run_audit(args=("discover",), arp=True, ARP_FAIL="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(files["live-hosts.txt"].splitlines()), 3)

    def test_empty_discovery(self):
        result, _, calls = self.run_audit(EMPTY="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No live hosts", result.stdout)
        self.assertEqual(len([c for c in calls if c[0] == "nmap"]), 1)

    def test_discovery_command_failure(self):
        result, _, _ = self.run_audit(FAIL_STAGE="pingscan")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Discovery failed", result.stdout)
        self.assertNotIn("No live hosts", result.stdout)

    def test_invalid_or_excessive_target_never_scans(self):
        for target in ("--script=brute", "999.1.1.1/24", "10.0.0.0/8"):
            with self.subTest(target=target):
                result, _, calls = self.run_audit(inputs=target + "\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[0] in ("nmap", "arp-scan") for c in calls))

    def test_failed_stage_is_reported_and_returns_nonzero(self):
        result, files, _ = self.run_audit(FAIL_STAGE="tcp-all")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failed", files["summary.txt"])
        self.assertIn("tcp-all", files["summary.txt"])

    def test_host_timeout_is_incomplete(self):
        result, files, _ = self.run_audit(PARTIAL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete", files["summary.txt"])

    def test_auth_requires_opt_in_and_snmp_uses_udp(self):
        result, _, calls = self.run_audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scans = [c for c in calls if c[0] == "nmap"]
        http = next(c for c in scans if c[-1].endswith("nse-http"))
        self.assertNotIn("http-default-accounts", " ".join(http))
        snmp = next(c for c in scans if c[-1].endswith("nse-snmp"))
        self.assertIn("-sU", snmp)
        tcp = next(c for c in scans if c[-1].endswith("tcp-all"))
        self.assertNotIn("--min-rate", tcp)
        self.assertNotIn("15s", tcp)

    def test_opt_ins_preserved(self):
        result, _, calls = self.run_audit(inputs="\ny\ny\ny\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scans = [c for c in calls if c[0] == "nmap"]
        for stage in ("udp-top50", "nse-intrusive", "nse-brute"):
            self.assertTrue(any(c[-1].endswith(stage) for c in scans))
        http = next(c for c in scans if c[-1].endswith("nse-http"))
        self.assertIn("http-default-accounts", " ".join(http))

    def test_discover_skips_radio_setup(self):
        result, _, calls = self.run_audit(inputs="\n", args=("discover",), radio=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(c[0] in ("airmon-ng", "iw", "airodump-ng") for c in calls))

    def test_failed_monitor_never_captures(self):
        result, _, calls = self.run_audit(inputs="\nn\nn\nn\ny\ny\n", radio=True, MON_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "airodump-ng" for c in calls))
        self.assertFalse(any(c[:3] == ["airmon-ng", "check", "kill"] for c in calls))

    def test_capture_failure_still_cleans_up_with_sudo(self):
        result, _, calls = self.run_audit(inputs="\nn\nn\nn\ny\ny\n", radio=True, CAPTURE_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(["airmon-ng", "stop", "wlan0mon"], calls)
        self.assertTrue(any(c[0] == "sudo" and "airmon-ng" in c and "stop" in c for c in calls))

    def test_partial_monitor_setup_is_cleaned_up(self):
        result, _, calls = self.run_audit(inputs="\nn\nn\nn\ny\ny\n", radio=True, MON_PARTIAL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(["airmon-ng", "stop", "wlan0mon"], calls)
        self.assertFalse(any(c[0] == "airodump-ng" for c in calls))

    def test_legacy_entry_forwards(self):
        legacy = SCRIPT.parents[2] / "network-utils/network/wifibrute.sh"
        result, _, calls = self.run_audit(inputs="\n", args=("discover",), entry=legacy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len([c for c in calls if c[0] == "nmap"]), 1)

    def test_ids_startup_failure_is_visible(self):
        result, files, _ = self.run_audit(inputs="\nn\nn\nn\ny\ny\n", ids=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("suricata\tfailed\t3", files["summary.txt"])

    def test_intrusive_does_not_override_brute_decline(self):
        result, _, calls = self.run_audit(inputs="\nn\ny\nn\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        intrusive = next(c for c in calls if c[0] == "nmap" and c[-1].endswith("nse-intrusive"))
        self.assertIn("not (brute or auth)", " ".join(intrusive))


if __name__ == "__main__":
    unittest.main()
