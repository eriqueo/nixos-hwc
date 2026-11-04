import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import release


INVENTORY = {
    'law': {'owner': 'workspace/nixos-dev', 'kind': 'governance'},
    'fleet': {'owner': 'workspace/nixos-dev', 'kind': 'shared'},
    'desktop': {'owner': 'domains/home', 'kind': 'integration'},
    'mail': {'owner': 'domains/mail', 'kind': 'integration'},
    'media': {'owner': 'domains/media', 'kind': 'integration'},
}


class ReleaseContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'fixture')
        self.git('config', 'core.hooksPath', '/dev/null')
        self.file = self.repo / 'domains/home/apps/waybar/parts/appearance.nix'
        self.file.parent.mkdir(parents=True)
        self.file.write_text('{}')
        self.git('add', '--', str(self.file))
        self.git('commit', '-m', 'base')
        self.base = release.revision(self.repo, 'HEAD')
        self.git('checkout', '-b', 'feature')
        self.file.write_text('{ changed = true; }')
        self.git('commit', '-am', 'desktop')
        self.candidate = release.revision(self.repo, 'HEAD')
        self.git('checkout', 'main')

    def git(self, *args):
        return release.git(self.repo, *args)

    def test_selected_leaf_and_intervening_changes(self):
        paths = release.changed(self.repo, self.candidate, [self.base])
        names, _ = release.select(INVENTORY, paths)
        self.assertEqual(names, ['desktop', 'fleet', 'law', 'mail'])
        self.git('checkout', 'feature')
        (self.repo / 'flake.lock').write_text('{}')
        self.git('add', '--', 'flake.lock')
        self.git('commit', '-m', 'lock')
        newer = release.revision(self.repo, 'HEAD')
        self.assertEqual(release.select(INVENTORY, release.changed(self.repo, newer,
                         [self.candidate, self.base]))[0], sorted(INVENTORY))

    def test_unknown_home_baseline_and_shared_inputs_broaden(self):
        for paths in (None, {'flake.lock'}, {'flake.nix'}, {'unmapped'}, {'domains/lib/hm.nix'}):
            self.assertEqual(release.select(INVENTORY, paths)[0], sorted(INVENTORY))
        self.assertIsNone(release.changed(self.repo, self.candidate, [None]))
        self.assertIsNone(release.active_revision('home'))

    def test_rename_and_delete_broaden(self):
        self.git('checkout', 'feature')
        self.git('mv', str(self.file), str(self.file.with_name('renamed.nix')))
        self.git('commit', '-m', 'rename')
        self.assertIsNone(release.changed(self.repo, release.revision(self.repo, 'HEAD'), [self.base]))
        self.git('rm', str(self.file.with_name('renamed.nix')))
        self.git('commit', '-m', 'delete')
        self.assertIsNone(release.changed(self.repo, release.revision(self.repo, 'HEAD'), [self.candidate]))

    def test_failed_required_build_cannot_move_main(self):
        with tempfile.TemporaryDirectory() as temp:
            nix = Path(temp) / 'nix'
            nix.write_text(f'#!{sys.executable}\nimport sys\n'
                           f'if sys.argv[1] == "eval": print({json.dumps(INVENTORY)!r})\n'
                           'else: sys.exit(17)\n')
            nix.chmod(0o755)
            with patch.object(release, 'active_revision', return_value=self.base), \
                 patch.dict(os.environ, PATH=temp + ':' + os.environ['PATH']):
                with self.assertRaises(subprocess.CalledProcessError) as failure:
                    release.release(self.repo, self.candidate, socket.gethostname(), 'system', 'merge')
                self.assertEqual(failure.exception.returncode, 17)
        self.assertEqual(release.revision(self.repo, 'main'), self.base)
        self.assertEqual(release.revision(self.repo, 'HEAD'), self.base)

    def test_changed_main_or_generation_invalidates_results(self):
        with patch.object(release, 'active_revision', return_value=self.base):
            token = release.snapshot(self.repo, self.candidate, 'system')
            self.git('merge', '--ff-only', self.candidate)
            with self.assertRaisesRegex(ValueError, 'stale'):
                release.unchanged(self.repo, token)
        with patch.object(release, 'active_revision', return_value='another-generation'):
            with self.assertRaisesRegex(ValueError, 'stale'):
                release.unchanged(self.repo, token)

    def test_no_receipt_can_authorize_another_candidate(self):
        with patch.object(release, 'verify', side_effect=ValueError('required check failed')) as verify:
            with self.assertRaises(ValueError):
                release.release(self.repo, self.candidate, socket.gethostname(), 'system', 'merge')
            self.assertEqual(verify.call_args.args[1], self.candidate)
        self.assertEqual(release.revision(self.repo, 'main'), self.base)

    def test_home_lane_cannot_skip_pending_system_changes(self):
        self.git('checkout', 'feature')
        (self.repo / 'flake.lock').write_text('{}')
        self.git('add', '--', 'flake.lock')
        self.git('commit', '-m', 'system input')
        candidate = release.revision(self.repo, 'HEAD')
        with patch.object(release, 'active_revision', return_value=self.base):
            with self.assertRaisesRegex(ValueError, 'system or mixed'):
                release.verify(self.repo, candidate, socket.gethostname(), 'home')


if __name__ == '__main__':
    unittest.main()
