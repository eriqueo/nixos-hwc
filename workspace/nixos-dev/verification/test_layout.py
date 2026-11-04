from pathlib import Path
import tempfile
import unittest
import layout


class LayoutContract(unittest.TestCase):
    def test_actual_syntax_and_mutations(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'domains/home').mkdir(parents=True)
            flake = root / 'flake.nix'
            flake.write_text('{ checks.${system} = verification.checks; }')
            layout.inspect(root)
            for mutation in (
                '{ checks.${system} = { inline = pkgs.runCommand "bad" {} ""; }; }',
                '{ checks.${system} = verification.checks // { extra = x; }; }',
                '{ checks.${system} = verification.checks; checks.other = x; }',
                '{ checks.${system} = ',
            ):
                flake.write_text(mutation)
                with self.assertRaises(ValueError):
                    layout.inspect(root)
            flake.write_text('{ checks.${system} = verification.checks; }')
            module = root / 'domains/home/index.nix'
            module.write_text('{ imports = [ ./verification/checks.nix ]; }')
            with self.assertRaises(ValueError):
                layout.inspect(root)
            module.unlink()
            module.parent.joinpath('verification').mkdir()
            module.parent.joinpath('verification/index.nix').write_text('{}')
            with self.assertRaises(ValueError):
                layout.inspect(root)
