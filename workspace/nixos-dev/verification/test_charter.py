import json
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

    def test_rules_do_not_match_their_own_definition(self):
        self.put('workspace/nixos-dev/verification/charter.py', Path(charter.__file__).read_text())
        for law in charter.LAWS:
            self.assertEqual(charter.inspect(self.root, law), [])


if __name__ == '__main__':
    unittest.main()
