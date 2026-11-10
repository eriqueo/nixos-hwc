import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import charter


class CharterContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.put('domains/home/index.nix', '{}')
        self.put('domains/home/README.md', '\n'.join('## ' + x for x in
                 ('Purpose', 'Boundaries', 'Structure', 'Changelog')))
        self.put('profiles/base/home.nix', '{}')
        self.put('flake.nix', '{}')

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_each_rule_rejects_a_violation(self):
        fixtures = {
            1: ('domains/home/bad.nix', 'x = osConfig.foo;'),
            2: ('domains/home/bad.nix', 'hwc.services.foo = true;'),
            4: ('domains/home/bad.nix', 'PGID = 1000;'),
            5: ('domains/home/bad.nix', 'virtualisation.oci-containers.containers.foo = {};'),
            7: ('domains/home/bad/index.nix', 'import ./sys.nix'),
            10: ('domains/home/bad.nix', 'x = lib.mkEnableOption "x";'),
            12: ('domains/home/README.md', 'missing sections'),
            14: ('flake.nix', 'github:eriqueo/nixos-hwc'),
            16: ('profiles/base/home.nix', 'x = pkgs.writeShellScript "bad" "";'),
        }
        for law, (name, content) in fixtures.items():
            with self.subTest(law=law):
                self.assertEqual(charter.inspect(self.root, law), [])
                path = self.root / name
                old = path.read_text() if path.exists() else None
                self.put(name, content)
                self.assertTrue(charter.inspect(self.root, law))
                if old is None:
                    path.unlink()
                else:
                    path.write_text(old)

    def test_cli_does_not_hide_unreadable_or_missing_input(self):
        path = self.put('domains/home/bad.nix', '{}')
        path.chmod(0)
        self.addCleanup(path.chmod, 0o600)
        result = subprocess.run([sys.executable, str(Path(charter.__file__)),
                                 '--root', str(self.root), '--law', '1'], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)['status'], 'tool-error')
        result = subprocess.run([sys.executable, str(Path(charter.__file__)),
                                 '--root', str(self.root / 'missing')], capture_output=True)
        self.assertEqual(result.returncode, 2)

    def readme_cli(self, *args):
        script = os.environ.get('HWC_README_GENERATOR',
                                str(Path(__file__).resolve().parents[1] / 'generate-domain-readmes.py'))
        return subprocess.run([sys.executable, script, '--repo-root', str(self.root), *args],
                              capture_output=True, text=True)

    def test_readme_cli_matches_current_rule_scope_and_rejects_missing_heading(self):
        self.put('domains/home/apps/example/README.md', 'Module documentation')
        self.put('domains/home/apps/example/parts/helper.nix', '{}')
        self.assertEqual(self.readme_cli('--check').returncode, 0)
        self.put('domains/home/README.md', '## Purpose\n## Boundaries\n## Structure\n')
        result = self.readme_cli('--check')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('Changelog', result.stdout)
        self.assertTrue(charter.inspect(self.root, 12))

    def test_readme_generation_is_current_and_preserves_existing_documents(self):
        self.put('domains/server/index.nix', '{}')
        readme = self.root / 'domains/server/README.md'
        original = (self.root / 'domains/home/README.md').read_bytes()
        self.assertEqual(self.readme_cli('--generate', '--dry-run').returncode, 0)
        self.assertFalse(readme.exists())
        result = self.readme_cli('--generate')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        content = readme.read_text()
        self.assertEqual([line[3:] for line in content.splitlines() if line.startswith('## ')],
                         list(charter.README_SECTIONS))
        self.assertIn('index.nix', content)
        self.assertNotIn('options.nix', content)
        self.assertEqual((self.root / 'domains/home/README.md').read_bytes(), original)
        self.assertEqual(self.readme_cli('--check').returncode, 0)
        self.assertEqual(charter.inspect(self.root, 12), [])

    def test_permission_report_processes_every_violation_without_early_exit(self):
        script = os.environ.get('HWC_PERMISSION_LINTER',
                                str(Path(__file__).resolve().parents[1] / 'lints/permission-lint.sh'))
        scope = self.root / 'fixture'
        self.put('fixture/one.nix', 'PGID = "1000";')
        self.put('fixture/two.nix', 'PGID = "1000";')
        result = subprocess.run(['bash', script, str(scope)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('one.nix', result.stdout)
        self.assertIn('two.nix', result.stdout)
        self.assertIn('Summary', result.stdout)

    def test_rules_do_not_match_their_own_definition(self):
        self.put('workspace/nixos-dev/verification/charter.py', Path(charter.__file__).read_text())
        for law in charter.LAWS:
            self.assertEqual(charter.inspect(self.root, law), [])


if __name__ == '__main__':
    unittest.main()
