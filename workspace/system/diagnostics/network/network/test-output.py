#!/usr/bin/env python3
"""Replay output paths with fake probes. No live network or sudo actions.

Run: python3 workspace/system/diagnostics/network/network/test-output.py
Fixtures and script reports are throwaway data, removed after each test run.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
SCRIPTS = sorted(p for p in ROOT.glob('*.sh') if p.name != 'network-report.sh')

# One dispatcher provides isolated command adapters. A restricted PATH keeps
# optional tools absent unless explicitly enabled by a fixture.
PROBES = r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['PROBE_LOG'], 'a') as f:
    f.write(name + ' ' + ' '.join(args) + '\n')
scenario = os.environ.get('SCENARIO', 'healthy')
if name == 'sudo':
    if args == ['-v']: sys.exit(0)
    if args[0] == '-n': args = args[1:]
    if args[0] == 'install': sys.exit(0)
    os.execvp(args[0], args)
elif name == 'timeout':
    if args[0] == '-k': args = args[2:]
    args = args[1:]
    if args[0] == 'bash': sys.exit(1 if scenario == 'offline' else 0)
    os.execvp(args[0], args)
elif name == 'ip':
    if 'route' in args:
        if scenario != 'no-route': print('default via 192.168.0.1 dev wlan0')
    elif 'addr' in args: print('2: wlan0 inet 192.168.0.136/24 scope global wlan0')
    else: print('2: wlan0: state UP')
elif name == 'ipcalc':
    print('PREFIX=24' if '-p' in args else 'NETWORK=192.168.0.0')
elif name == 'resolvectl':
    if args[0] == 'dns': print('Link 2 (wlan0): 192.168.0.1')
    else: print('Link 2 (wlan0)\n    Current DNS Server: 192.168.0.1\n    DNS Servers: 192.168.0.1')
elif name == 'dig':
    if scenario in ('empty-dns', 'offline'): sys.exit(0)
    if scenario == 'public-dns-only' and not any(a.startswith('@') for a in args): sys.exit(0)
    if scenario == 'matrix-gap' and '@9.9.9.9' in args: sys.exit(0)
    if scenario == 'dns-repair' and not any(a.startswith('@') for a in args):
        if 'resolvectl dns wlan0' not in Path(os.environ['PROBE_LOG']).read_text(): sys.exit(0)
    print('142.250.1.1' if '+short' in args else ';; ->>HEADER<<- status: NOERROR\ngoogle.com. 300 IN A 142.250.1.1\n;; Query time: 12 msec')
elif name == 'ping':
    if scenario == 'offline': sys.exit(1)
    print('rtt min/avg/max/mdev = 2.0/3.0/4.0/0.2 ms')
elif name == 'nmap':
    if scenario == 'scan-timeout': print('Skipping host due to host timeout'); sys.exit(0)
    if scenario == 'failed-scan': sys.exit(1)
    discovery = '-sn' in args
    text = ('Nmap scan report for 192.168.0.1\nHost is up (0.01s latency).\n'
            'MAC Address: 50:3D:D1:77:21:D6 (TP-Link)\n')
    if not discovery:
        text += 'PORT STATE SERVICE\n53/tcp open domain\n80/tcp open http\n443/tcp open https\n'
        text += '| State: NOT VULNERABLE\n'
        if scenario == 'vulnerability': text += '| State: VULNERABLE\n'
        if scenario == 'cleartext': text += '23/tcp open telnet\n'
    if '-oA' in args:
        prefix = Path(args[args.index('-oA')+1])
        prefix.with_suffix('.nmap').write_text(text)
        prefix.with_suffix('.gnmap').write_text('Host: 192.168.0.1 ()\tStatus: Up\n')
        host = '<host timedout="true"/>' if scenario == 'partial-audit' and not discovery else ''
        if scenario == 'credential-lead' and 'brute,auth' in args:
            host = '<host><script><elem>admin:fixture-secret => Valid credentials</elem></script></host>'
        prefix.with_suffix('.xml').write_text('<nmaprun>'+host+'<runstats><finished exit="success"/></runstats></nmaprun>\n')
    print(text)
elif name in ('mtr', 'traceroute'):
    print('HOST: laptop Loss%\n1. router 66.7%\n2. destination 0.0%')
elif name == 'ss':
    print('Netid State Local Address:Port\nudp UNCONN 127.0.0.53:53')
elif name == 'curl': print('redirect' if scenario == 'portal-response' else 'success')
elif name == 'iw':
    if 'scan' in args:
        print('BSS 50:3d:d1:77:21:d6\n\tsignal: -50.0 dBm\n\tSSID: home')
    elif 'link' in args: print('Connected\n\tSSID: home\n\tsignal: '+('-80' if scenario == 'weak-radio' else '-50')+' dBm')
    else: print('Interface wlan0\n type managed')
elif name == 'wash': print('BSSID Channel WPS Locked\n50:3d:d1:77:21:d6 6 2.0 No'); sys.exit(124)
elif name == 'airodump-ng':
    prefix = Path(args[args.index('--write')+1])
    prefix.with_name(prefix.name+'-01.csv').write_text('BSSID,first,last,channel,speed,privacy\n50:3d:d1:77:21:d6,x,x,6,54,WPA2\n')
    sys.exit(124)
elif name == 'tcpdump':
    Path(args[args.index('-w')+1]).write_bytes(b'fixture-packet-data'); sys.exit(124)
elif name == 'ls':
    # Match ordinary ls behavior; do not rely on the host's eza alias.
    os.execv(os.environ['REAL_LS'], ['ls', *args])
elif name in ('systemctl', 'airmon-ng', 'nmcli', 'sleep', 'chown'): pass
else: sys.exit(1)
'''


class OutputTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='network-output-')
        self.addCleanup(self.tmp.cleanup)
        self.cwd = Path(self.tmp.name)
        self.scripts = self.cwd / 'scripts'
        self.scripts.mkdir()
        # Bind the two legacy fixed report paths to this throwaway run so tests
        # cannot overwrite a user's /tmp diagnostic reports. Probe code is unchanged.
        for script in ROOT.glob('*.sh'):
            source = script.read_text()
            for filename in ('netcheck_results.env', 'netprobe_results.txt'):
                source = source.replace('/tmp/'+filename, str(self.cwd/filename))
            (self.scripts/script.name).write_text(source)
        self.bin = self.cwd / 'bin'
        self.bin.mkdir()
        # Real utilities manipulate only throwaway fixture/report files.
        for command in ('bash', 'dirname', 'awk', 'head', 'cut', 'grep', 'sed',
                        'tail', 'sort', 'tr', 'wc', 'cat', 'mkdir', 'date', 'tee',
                        'python3', 'uname', 'hostname', 'id', 'paste', 'env',
                        'rg', 'mktemp'):
            target = shutil.which(command)
            if target:
                (self.bin / command).symlink_to(target)
        self.dispatch = self.cwd / 'probe'
        self.dispatch.write_text(PROBES)
        self.dispatch.chmod(0o755)
        for command in ('sudo', 'timeout', 'ip', 'ipcalc', 'resolvectl', 'dig',
                        'ping', 'nmap', 'mtr', 'traceroute', 'ss', 'curl', 'iw',
                        'systemctl', 'nmcli', 'sleep', 'ls', 'chown'):
            (self.bin / command).symlink_to(self.dispatch)
        self.env = {**os.environ, 'PATH': str(self.bin),
                    'PROBE_LOG': str(self.cwd / 'commands.log'),
                    'REAL_LS': shutil.which('ls'), 'NO_COLOR': '1'}
        self.env.pop('BASH_ENV', None)

    def run_script(self, name, *args, scenario='healthy', answers=None):
        if answers is None:
            answers = ('\n' if name == 'wifibrute.sh' else '') + 'n\n'*20
        env = {**self.env, 'SCENARIO': scenario}
        result = subprocess.run([str(self.bin/'bash'), str(self.scripts/name), *args],
                                cwd=self.cwd, env=env, input=answers, text=True,
                                capture_output=True, timeout=10)
        return result

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Checking:', result.stdout)
        self.assertIn('Meaning:', result.stdout)
        self.assertNotIn('\x1b', result.stdout)

    def test_help_never_probes(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result = self.run_script(script.name, '--help')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Purpose:', result.stdout)
                self.assertIn('Effect:', result.stdout)
                self.assertIn('--details', result.stdout)
        self.assertFalse((self.cwd/'commands.log').exists())

    def test_each_tool_has_outcome_and_next_action(self):
        for name, args in [('quicknet.sh', ()), ('advnetcheck.sh', ()),
                           ('advnetcheck2.sh', ('--detailed',)),
                           ('homewifi-audit.sh', ()), ('netcheck.sh', ('-f',)),
                           ('wifibrute.sh', ()), ('hw-overview.sh', ()),
                           ('toolscan.sh', ())]:
            with self.subTest(script=name):
                result = self.run_script(name, *args)
                self.assertEqual(result.returncode, 1 if name == 'toolscan.sh' else 0,
                                 result.stderr)
                self.assertIn('TLDR', result.stdout)
                self.assertNotIn('The run ended before a full conclusion', result.stdout)
                tldr = result.stdout.split('TLDR')[-1]
                self.assertIn('Because:', tldr)
                self.assertIn('Next:', tldr)
                self.assertIn('Limits:', tldr)

    def test_connection_tldr_changes_with_dns_and_timeout(self):
        for name in ('quicknet.sh', 'advnetcheck.sh'):
            with self.subTest(script=name):
                healthy = self.run_script(name).stdout.split('TLDR')[-1]
                dns = self.run_script(name, scenario='empty-dns').stdout.split('TLDR')[-1]
                silent = self.run_script(name, scenario='scan-timeout').stdout.split('TLDR')[-1]
                self.assertIn('Basic connection probes passed', healthy)
                self.assertIn('DNS needs attention', dns)
                self.assertIn('Public access is unconfirmed', silent)
                self.assertNotIn('Basic connection probes passed', silent)

    def test_configured_dns_failure_survives_public_dns_success(self):
        for name, args in [('advnetcheck.sh', ()), ('advnetcheck2.sh', ('--detailed',))]:
            with self.subTest(script=name):
                result = self.run_script(name, *args, scenario='public-dns-only')
                self.assert_ok(result)
                self.assertIn('Configured DNS needs attention; public DNS answered', result.stdout)
                self.assertNotIn('Basic connection probes passed', result.stdout)

    def test_skipped_dns_is_untested(self):
        (self.bin/'dig').unlink()
        result = self.run_script('advnetcheck.sh')
        self.assertIn('DNS remains untested', result.stdout)
        self.assertNotIn('Basic connection probes passed', result.stdout)

    def test_dns_matrix_gaps_are_not_hidden(self):
        for name, args in [('advnetcheck.sh', ()), ('advnetcheck2.sh', ('--detailed',))]:
            with self.subTest(script=name):
                result = self.run_script(name, *args, scenario='matrix-gap')
                self.assert_ok(result)
                self.assertIn('some DNS comparison lookups returned no address', result.stdout)
                self.assertNotIn('no fault appeared', result.stdout)

    def test_requested_dns_repair_updates_final_state(self):
        result = self.run_script('netcheck.sh', scenario='dns-repair', answers='y\nn\nn\n')
        self.assert_ok(result)
        self.assertIn('Basic connection probes passed', result.stdout.split('TLDR')[-1])

    def test_early_exit_keeps_partial_tldr_and_exit_code(self):
        for name in ('quicknet.sh', 'advnetcheck.sh', 'wifibrute.sh'):
            with self.subTest(script=name):
                result = self.run_script(name, scenario='no-route')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('TLDR', result.stdout)
                self.assertIn('Unfinished checks are untested', result.stdout)
        result = self.run_script('wifibrute.sh', scenario='failed-scan')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stage status:', result.stdout)
        self.assertIn('TLDR', result.stdout)

    def test_purpose_specific_wifi_and_security_tldrs(self):
        weak = self.run_script('homewifi-audit.sh', scenario='weak-radio')
        self.assertIn('Weak WiFi signal is a lead', weak.stdout)
        for scenario, outcome in [('vulnerability', 'Vulnerability scripts reported leads'),
                                  ('cleartext', 'FTP or Telnet ports answered'),
                                  ('partial-audit', 'The audit is incomplete')]:
            with self.subTest(scenario=scenario):
                result = self.run_script('wifibrute.sh', scenario=scenario)
                self.assertIn(outcome, result.stdout)
                self.assertEqual(result.returncode, 1 if scenario == 'partial-audit' else 0)
                self.assertIn('TLDR', next(self.cwd.glob('reports/*/summary.txt')).read_text())

    def test_credential_tldr_does_not_print_secrets(self):
        result = self.run_script('wifibrute.sh', scenario='credential-lead', answers='\nn\nn\ny\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Credential scripts reported login leads', result.stdout)
        self.assertNotIn('fixture-secret', result.stdout.split('TLDR')[-1])

    def test_browser_check_and_declined_detail(self):
        result = self.run_script('advnetcheck2.sh', scenario='portal-response')
        self.assertIn('Browser access needs attention', result.stdout)
        self.assertNotIn('Basic connection probes passed', result.stdout)
        result = self.run_script('netcheck.sh', scenario='offline')
        self.assertIn('TLDR', result.stdout)
        self.assertNotIn('Basic connection probes passed', result.stdout)

    def test_connection_outputs_and_dns_server_boundary(self):
        for name, args in [('quicknet.sh', ()), ('advnetcheck.sh', ()),
                           ('advnetcheck2.sh', ('--detailed',)),
                           ('homewifi-audit.sh', ()), ('netcheck.sh', ('-f',))]:
            with self.subTest(script=name):
                self.assert_ok(self.run_script(name, *args))
        log = (self.cwd/'commands.log').read_text()
        self.assertNotIn('@(wlan0)', log)

    def test_empty_dns_is_not_success(self):
        for name in ('quicknet.sh', 'advnetcheck.sh'):
            with self.subTest(script=name):
                result = self.run_script(name, scenario='empty-dns')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('DNS lookups succeeded', result.stdout)
                self.assertNotIn('System DNS returned an address', result.stdout)

    def test_timeout_is_not_public_access_success(self):
        result = self.run_script('quicknet.sh', scenario='scan-timeout')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Public service probes: unknown', result.stdout)
        self.assertNotIn('At least one tested public service port answered', result.stdout)

    def test_security_discovery_and_skipped_checks(self):
        result = self.run_script('wifibrute.sh', answers='\nn\nn\nn\n')
        self.assert_ok(result)
        self.assertIn('Discovered 1 host', result.stdout)
        self.assertIn('[SKIP]', result.stdout)
        summary = next(self.cwd.glob('reports/*/summary.txt')).read_text()
        self.assertNotIn('NOT VULNERABLE', summary)
        self.assertTrue(next(self.cwd.glob('reports/*/nse-safe.nmap')).is_file())

    def test_inventory_handles_absent_optional_tools(self):
        self.assert_ok(self.run_script('hw-overview.sh'))
        result = self.run_script('toolscan.sh')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Missing rows do not prevent every network script', result.stdout)

    def test_survey_expected_timeout_reaches_summary(self):
        for command in ('airmon-ng', 'wash', 'airodump-ng', 'tcpdump'):
            (self.bin/command).symlink_to(self.dispatch)
        result = self.run_script('wifisurvery.sh', '-i', 'wlan0')
        self.assert_ok(result)
        self.assertIn('Full summary:', result.stdout)
        self.assertTrue(list(self.cwd.glob('wifi_report_*/SUMMARY.txt')))
        self.assertIn('TLDR', next(self.cwd.glob('wifi_report_*/SUMMARY.txt')).read_text())
        self.assertIn('Access point observations were captured', result.stdout)
        self.assertIn('systemctl restart', (self.cwd/'commands.log').read_text())

    def test_evidence_excerpts_consume_full_stream(self):
        code = 'source "$1"; report_init t p e u "$2"; seq 1 25 | report_evidence'
        for option, omitted in [('', True), ('--details', False)]:
            result = subprocess.run(['bash', '-c', code, '_', str(ROOT/'network-report.sh'), option],
                                    text=True, capture_output=True, check=True)
            self.assertEqual('9 more lines' in result.stdout, omitted)
            if not omitted:
                self.assertIn('    25\n', result.stdout)

    def test_saved_tldr_is_plain_text(self):
        target = self.cwd/'summary.txt'
        code = ('source "$1"; report_init t p e u; '
                'BOLD=$\'\\033[1m\'; GREEN=$\'\\033[32m\'; NC=$\'\\033[0m\'; '
                'REPORT_TLDR_FILE=$2; report_tldr PASS outcome evidence action limits')
        result = subprocess.run(['bash', '-c', code, '_', str(ROOT/'network-report.sh'), str(target)],
                                text=True, capture_output=True, check=True)
        self.assertIn('\x1b', result.stdout)
        self.assertNotIn('\x1b', target.read_text())
        self.assertIn('Because: evidence', target.read_text())

    def test_unexpected_failure_explains_incomplete_run(self):
        code = 'set -e; source "$1"; report_init t p e u; report_heading "DNS comparison"; false'
        result = subprocess.run(['bash', '-c', code, '_', str(ROOT/'network-report.sh')],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('DNS comparison', result.stderr)
        self.assertIn('This run is incomplete', result.stderr)
        self.assertIn('Next:', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
