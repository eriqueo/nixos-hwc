"""Run generated tunnel followers with local API and service-control adapters.

checks.nix owns the evaluated fixture. This file tests command behavior rather
than rendering assertions; no VPN, client, secret or running service is used.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

fixture = json.loads(Path(sys.argv[1]).read_text())
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    tools = root / "bin"
    tools.mkdir()
    adapter = tools / "adapter"
    adapter.write_text("#!" + sys.executable + "\n" + r'''
import json, os
from pathlib import Path
import sys
root = Path(os.environ['PROBE_ROOT'])
name = Path(sys.argv[0]).name
if name == 'curl':
    target = next((v for v in sys.argv if v.startswith('http://')), '')
    if target.endswith('/v1/portforward'):
        count = int((root/'polls').read_text()) + 1 if (root/'polls').exists() else 1
        (root/'polls').write_text(str(count))
        print(json.dumps({'port':50001 if count >= 4 else 50000}))
    elif target.endswith('/auth/login'):
        if not os.environ.get('AUTH_FAIL'): print('SID\tfixture')
    elif target.endswith('/setPreferences'):
        with (root/'updates').open('a') as output:
            output.write(sys.argv[sys.argv.index('--data')+1]+'\n')
        if os.environ.get('UPDATE_FAIL'): sys.exit(22)
    else: raise SystemExit('unexpected fixture URL')
elif name == 'sleep':
    count = int((root/'sleeps').read_text()) + 1 if (root/'sleeps').exists() else 1
    (root/'sleeps').write_text(str(count))
    if count >= int(os.environ.get('ITERATIONS','3')): sys.exit(99)
elif name == 'systemctl':
    assert (root/'gluetun-slskd/forwarded-port').read_text() == '50000'
    with (root/'units').open('a') as output: output.write(' '.join(sys.argv[1:])+'\n')
''')
    adapter.chmod(0o755)
    for name in ("curl", "sleep", "systemctl"):
        (tools / name).symlink_to(adapter)
    env = {"PATH": str(tools) + os.pathsep + os.environ["PATH"], "PROBE_ROOT": str(root)}

    def run(name, **values):
        source = Path(fixture[name]).read_text().replace(fixture["stateRoot"], str(root))
        return subprocess.run(["bash", "-c", source], env={**env, **values},
                              capture_output=True, text=True, timeout=10)

    result = run("qbittorrent")
    assert result.returncode == 99, result.stderr
    assert (root / "updates").read_text().splitlines() == [
        'json={"listen_port":50000}', 'json={"listen_port":50001}']
    assert (root / "gluetun/forwarded-port").read_text() == "50001"
    for name in ("polls", "sleeps", "updates"):
        (root / name).unlink()
    failed = run("qbittorrent", UPDATE_FAIL="1")
    assert failed.returncode != 0 and failed.returncode != 99, failed.stderr
    assert (root / "gluetun/forwarded-port").read_text() == "50000"
    recovered = run("qbittorrent", ITERATIONS="1")
    assert recovered.returncode == 99, recovered.stderr
    assert len((root / "updates").read_text().splitlines()) == 2, "failed update was acknowledged"
    for name in ("polls", "sleeps", "updates"):
        (root / name).unlink()
    failed = run("qbittorrent", AUTH_FAIL="1")
    assert failed.returncode != 0 and failed.returncode != 99
    assert not (root / "updates").exists()
    (root / "polls").unlink()
    result = run("slskd", ITERATIONS="1")
    assert result.returncode == 99, result.stderr
    assert (root / "units").read_text().splitlines() == [
        "restart slskd-config-generator.service", "restart podman-slskd.service"]
print("actual tunnel followers sync once per port, retry failed updates and publish before client actions")
