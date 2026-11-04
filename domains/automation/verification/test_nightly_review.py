"""Execute the generated morning-review wrapper against isolated effect ports."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

fixture = json.loads(Path(sys.argv[1]).read_text())
original = Path(fixture['script']).read_text()
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    cli = bin_dir / 'review'
    cli.write_text(f'#!{sys.executable}\nimport os, sys\nprint(os.environ["SUMMARY"])\n'
                   'print("human log", file=sys.stderr)\nsys.exit(int(os.environ["REVIEW_EXIT"]))\n')
    curl = bin_dir / 'curl'
    curl.write_text(f'#!{sys.executable}\nimport json, os, sys\n'
                    'with open(os.environ["EFFECTS"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
    for path in (cli, curl):
        path.chmod(0o755)
    assert fixture['cli'] in original, 'production CLI boundary changed'
    assert '/var/lib/refinery/reviews' in original, 'production audit boundary changed'
    script = original.replace(fixture['cli'], str(cli)).replace('/var/lib/refinery/reviews', str(root / 'audit'))
    quiet = {'reviewed': 0, 'opened': 0, 'byVerdict': {}, 'graduated': [], 'errors': []}
    def execute(source, summary, exit_code=0):
        effects = root / 'effects'
        effects.write_text('')
        result = subprocess.run(['bash', '-c', source], capture_output=True, text=True, timeout=10,
                                env=dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'],
                                         SUMMARY=json.dumps(summary) if isinstance(summary, dict) else summary,
                                         REVIEW_EXIT=str(exit_code), EFFECTS=str(effects),
                                         NB_NOTIFY_URL='https://fixture.invalid/notify'))
        calls = [json.loads(line) for line in effects.read_text().splitlines()]
        return result, calls
    cases = [(quiet, 0, None), (quiet | {'graduated': ['completed']}, 0, None),
             (quiet | {'opened': 1}, 0, 3),
             (quiet | {'byVerdict': {'merge-ready': 1}}, 0, 3),
             (quiet | {'errors': [{'id': 'item', 'error': 'failed'}]}, 0, 2),
             (quiet, 7, 2), ('malformed JSON', 0, 2)]
    for summary, exit_code, priority in cases:
        result, calls = execute(script, summary, exit_code)
        assert result.returncode == exit_code, (result.stdout, result.stderr)
        assert len(calls) == (0 if priority is None else 1), (summary, calls, result.stderr)
        if priority is not None:
            payload = json.loads(calls[0][calls[0].index('-d') + 1])
            assert payload['priority'] == priority, payload
        assert list((root / 'audit/_runs').glob('*-morning-review.json')), 'audit disappeared'
    # Revert the production effect gate: the quiet-path oracle must catch it.
    marker = 'if [ "$nb_notify" = 1 ] &&'
    assert marker in script
    _, calls = execute(script.replace(marker, 'if'), quiet)
    assert calls, 'seeded removal of notification gating escaped the behavioral oracle'
print('quiet, graduated, decisions, record errors, failed/malformed CLI and gate mutation pass')
