"""Replay production CLI with fake tools. Opt-in live test probes loopback only."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET

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
    if os.environ.get('LIVE_TCP_PORT') and prefix.name.startswith('tcp-svcos-'):
        # Only the production fingerprint command crosses into real tools.
        # Fail closed on any unexpected target or port; every other stage is fake.
        if (args[-3] != '127.0.0.1' or '-iL' in args or
                args[args.index('-p') + 1] != os.environ['LIVE_TCP_PORT']):
            sys.exit(5)
        os.execv(os.environ['REAL_SUDO'], [os.environ['REAL_SUDO'], '-n',
                                          os.environ['REAL_NMAP'], *args])
    if os.environ.get('REQUIRE_RESERVED'):
        for ext in ('.nmap', '.gnmap', '.xml'):
            path = Path(str(prefix) + ext)
            if not path.exists() or path.stat().st_uid != os.getuid():
                print('output was not reserved by the report owner', file=sys.stderr)
                sys.exit(4)
    if os.environ.get('FAIL_STAGE') == prefix.name:
        print('fixture scan failure', file=sys.stderr)
        sys.exit(3)
    hosts = '' if os.environ.get('EMPTY') else (
        'Host: 192.168.0.1 ()\tStatus: Up\n'
        'Host: 192.168.0.97 (hwc-home.local)\tStatus: Up\n'
        'Host: 192.168.0.136 (hwc-laptop.local)\tStatus: Up\n'
        'Host: 192.168.0.200 ()\tStatus: Down\n')
    if os.environ.get('LIVE_TCP_PORT'): hosts = 'Host: 127.0.0.1 ()\tStatus: Up\n'
    Path(str(prefix) + '.gnmap').write_text(hosts)
    Path(str(prefix) + '.nmap').write_text(
        'Skipping host 192.168.0.97 due to host timeout\n'
        if os.environ.get('PARTIAL') and prefix.name == 'tcp-all' else '')
    partial = os.environ.get('PARTIAL') and prefix.name == 'tcp-all'
    inventory = {'192.168.0.1': [80], '192.168.0.97': [54429, 62078],
                 '192.168.0.136': []}
    if os.environ.get('NO_PORTS'): inventory = {ip: [] for ip in inventory}
    if os.environ.get('PARTIAL_NO_PORTS'): inventory['192.168.0.97'] = []
    if os.environ.get('MISSING_HOST'): inventory.pop('192.168.0.97')
    if os.environ.get('MANY_PORTS') and prefix.name == 'tcp-all':
        inventory['192.168.0.97'] = list(range(1, 65536))
    if os.environ.get('SPARSE_PORTS') and prefix.name == 'tcp-all':
        inventory['192.168.0.97'] = list(range(1, 65536, 2))
    if os.environ.get('LIVE_TCP_PORT'): inventory = {'127.0.0.1': [int(os.environ['LIVE_TCP_PORT'])]}
    if prefix.name == 'tcp-followup': inventory = {'192.168.0.97': [443]}
    hosts_xml = ''.join(
        '<host timedout="' + ('true' if partial and ip == '192.168.0.97' else 'false') +
        '"><status state="up"/><address addr="' + ip + '" addrtype="ipv4"/><ports>' +
        ''.join('<port protocol="tcp" portid="' + str(p) + '"><state state="open"/></port>'
                for p in ports) +
        '<port protocol="tcp" portid="9999"><state state="closed"/></port>' +
        '<port protocol="udp" portid="161"><state state="open"/></port>' +
        '</ports></host>' for ip, ports in inventory.items())
    Path(str(prefix) + '.xml').write_text(
        '<nmaprun>' + hosts_xml + '<runstats><finished exit="success"/></runstats></nmaprun>')
    if os.environ.get('BAD_XML') and prefix.name == 'tcp-all':
        Path(str(prefix) + '.xml').write_text('<broken')
    if os.environ.get('BAD_FOLLOWUP_XML') and prefix.name == 'tcp-followup':
        Path(str(prefix) + '.xml').write_text('<broken')
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
                         "grep", "sed", "cat", "dirname", "sleep", "kill", "ls", "id", "chown"):
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
            env.pop("BASH_ENV", None)
            if flags.get("EXHAUST_BUDGET"):
                clock = root / "clock.sh"
                clock.write_text("trap 'case \"$BASH_COMMAND\" in REMAINING=*) SECONDS=999999 ;; esac' DEBUG\n")
                env["BASH_ENV"] = str(clock)
            result = subprocess.run(["bash", str(entry), *args], input=inputs,
                                    text=True, capture_output=True, cwd=root,
                                    env=env, timeout=90 if flags.get("LIVE_TCP_PORT") else 10)
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

    def test_fingerprints_each_hosts_discovered_ports(self):
        result, files, calls = self.run_audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scans = [c for c in calls if c[0] == "nmap" and "-sV" in c and "-O" in c]
        self.assertEqual(len(scans), 2)
        ports = {c[-3]: c[c.index("-p") + 1] for c in scans}
        self.assertEqual(ports, {"192.168.0.1": "80", "192.168.0.97": "54429,62078"})
        self.assertIn("tcp-svcos-192.168.0.136\tskipped\t0", files["stages.tsv"])
        self.assertIn("tcp-inventory.tsv", files)
        self.assertTrue(all(c[c.index("--host-timeout") + 1] == "60s" for c in scans))
        self.assertTrue(all("-iL" not in c for c in scans))

    def test_empty_tcp_inventory_never_falls_back_to_default_ports(self):
        result, files, calls = self.run_audit(NO_PORTS="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(c[0] == "nmap" and "-O" in c for c in calls))
        self.assertEqual(files["stages.tsv"].count("\tskipped\t0"), 3)

    def test_full_port_set_fits_in_one_explicit_argument(self):
        result, files, calls = self.run_audit(MANY_PORTS="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scan = next(c for c in calls if c[0] == "nmap" and c[-1].endswith("tcp-svcos-192.168.0.97"))
        self.assertEqual(scan[scan.index("-p") + 1], "1-65535")
        self.assertIn("192.168.0.97\t1-65535\tfull", files["tcp-inventory.tsv"])

    def test_sparse_port_set_is_partitioned_without_losing_ports(self):
        result, _, calls = self.run_audit(SPARSE_PORTS="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scans = [c for c in calls if c[0] == "nmap" and
                 c[-1].rsplit("/", 1)[-1].startswith("tcp-svcos-192.168.0.97-part")]
        self.assertGreater(len(scans), 1)
        specs = [c[c.index("-p") + 1] for c in scans]
        self.assertTrue(all(len(spec) <= 60000 for spec in specs))
        ports = [int(p) for spec in specs for p in spec.split(",")]
        self.assertEqual(ports, list(range(1, 65536, 2)))

    def test_exhausted_budget_records_untested_hosts_without_probing(self):
        result, files, calls = self.run_audit(EXHAUST_BUDGET="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "nmap" and "-O" in c for c in calls))
        for ip in ("192.168.0.1", "192.168.0.97"):
            self.assertIn(f"tcp-svcos-{ip}\tuntested\t124", files["stages.tsv"])

    def test_partial_followup_is_optional(self):
        result, files, calls = self.run_audit(PARTIAL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "nmap" and c[-1].endswith("tcp-followup") for c in calls))
        self.assertIn("192.168.0.97\t54429,62078\tpartial", files["tcp-inventory.tsv"])

    def test_followup_is_bounded_and_keeps_original_partial_report(self):
        result, files, calls = self.run_audit(inputs="\nn\nn\nn\ny\n", PARTIAL="1")
        self.assertNotEqual(result.returncode, 0)
        scans = [c for c in calls if c[0] == "nmap"]
        followup = next(c for c in scans if c[-1].endswith("tcp-followup"))
        self.assertEqual(followup[followup.index("--top-ports") + 1], "100")
        self.assertEqual(followup[followup.index("--host-timeout") + 1], "30s")
        self.assertEqual(files["tcp-timeout-hosts.txt"], "192.168.0.97\n")
        self.assertTrue(any(c[:5] == ["sudo", "-n", "timeout", "-k", "5s"] and
                            "120s" in c and "--top-ports" in c for c in calls))
        self.assertIn('timedout="true"', files["tcp-all.xml"])
        self.assertIn("192.168.0.97\t443,54429,62078\tpartial", files["tcp-inventory.tsv"])
        self.assertEqual(sum(c[-1].endswith("tcp-followup") for c in scans), 1)
        self.assertFalse(any("brute,auth" in c for c in scans))

    def test_failed_followup_keeps_known_ports(self):
        result, files, _ = self.run_audit(inputs="\nn\nn\nn\ny\n", PARTIAL="1",
                                         FAIL_STAGE="tcp-followup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tcp-followup\tfailed\t3", files["summary.txt"])
        self.assertIn("192.168.0.97\t54429,62078\tpartial", files["tcp-inventory.tsv"])

    def test_malformed_inventory_never_fingerprints_default_ports(self):
        result, files, calls = self.run_audit(BAD_XML="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tcp-inventory\tfailed", files["summary.txt"])
        self.assertFalse(any(c[0] == "nmap" and "-O" in c for c in calls))

    def test_missing_host_is_untested_instead_of_no_open_ports(self):
        result, files, _ = self.run_audit(MISSING_HOST="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("192.168.0.97\t-\tunavailable", files["tcp-inventory.tsv"])
        self.assertIn("tcp-svcos-192.168.0.97\tuntested\t0", files["stages.tsv"])

    def test_invalid_followup_preserves_original_inventory(self):
        result, files, _ = self.run_audit(inputs="\nn\nn\nn\ny\n", PARTIAL="1",
                                         BAD_FOLLOWUP_XML="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tcp-followup\tincomplete\t0", files["stages.tsv"])
        self.assertIn("192.168.0.97\t54429,62078\tpartial", files["tcp-inventory.tsv"])

    def test_timedout_host_without_ports_can_get_followup_ports(self):
        result, files, calls = self.run_audit(inputs="\nn\nn\nn\ny\n", PARTIAL="1",
                                             PARTIAL_NO_PORTS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("192.168.0.97\t443\tpartial", files["tcp-inventory.tsv"])
        scan = next(c for c in calls if c[0] == "nmap" and c[-1].endswith("tcp-svcos-192.168.0.97"))
        self.assertEqual(scan[scan.index("-p") + 1], "443")

    def test_followup_does_not_repeat_intrusive_or_auth_stages(self):
        result, _, calls = self.run_audit(inputs="\nn\ny\ny\ny\n", PARTIAL="1")
        self.assertNotEqual(result.returncode, 0)
        for stage in ("tcp-followup", "nse-intrusive", "nse-brute"):
            self.assertEqual(sum(c[0] == "nmap" and c[-1].endswith(stage) for c in calls), 1)

    @unittest.skipUnless(os.environ.get("WIFIBRUTE_LIVE_TEST") == "1", "opt-in loopback check")
    def test_live_loopback_fingerprinting(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Controlled wifibrute fixture\n")

            def log_message(self, *_):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                port = server.server_port
                self.assertGreaterEqual(port, 32768)
                result, files, _ = self.run_audit(
                    inputs="127.0.0.1/32\nn\nn\nn\n", LIVE_TCP_PORT=str(port),
                    REAL_SUDO=shutil.which("sudo"), REAL_NMAP=shutil.which("nmap"))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                root = ET.fromstring(files["tcp-svcos-127.0.0.1.xml"])
                found = root.find(f"host/ports/port[@portid='{port}']/service")
                self.assertIsNotNone(found)
                self.assertEqual(found.get("name"), "http")
                self.assertIn(f"{port}/tcp", files["tcp-svcos.nmap"])
                print(f"Live fingerprint: 127.0.0.1:{port} identified as {found.attrib}")
            finally:
                server.shutdown()
                thread.join(timeout=5)

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

    def test_output_files_reserved_before_privileged_scan(self):
        result, _, calls = self.run_audit(REQUIRE_RESERVED="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(c[:4] == ["sudo", "-n", "chown", "-hR"] for c in calls))

    def test_intrusive_does_not_override_brute_decline(self):
        result, _, calls = self.run_audit(inputs="\nn\ny\nn\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        intrusive = next(c for c in calls if c[0] == "nmap" and c[-1].endswith("nse-intrusive"))
        self.assertIn("not (brute or auth)", " ".join(intrusive))


if __name__ == "__main__":
    unittest.main()
