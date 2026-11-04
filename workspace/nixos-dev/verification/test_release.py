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

    def test_home_release_publishes_provenance_through_real_activation(self):
        home = self.repo / 'user'
        output = home / 'generation'
        output.mkdir(parents=True)
        pointer = home / '.local/state/home-manager/gcroots/current-home'
        pointer.parent.mkdir(parents=True)
        activator = output / 'activate'
        activator.write_text(f'#!{sys.executable}\nfrom pathlib import Path\n'
            f'Path({str(pointer)!r}).symlink_to({str(output)!r})\n')
        activator.chmod(0o700)
        # Owned fixture files must not make the Git checkout dirty.
        (self.repo / '.git/info/exclude').write_text('user/\n')
        with patch.object(Path, 'home', return_value=home), \
             patch.object(release, 'active_revision', return_value=self.base):
            token = release.snapshot(self.repo, self.candidate, 'home')
            with patch.object(release, 'verify', return_value=(token, str(output))):
                release.release(self.repo, self.candidate, socket.gethostname(), 'home', 'switch')
        self.assertEqual(release.home_revision(home, socket.gethostname()), self.candidate)
        known = release.changed(self.repo, self.candidate,
            [self.base, release.home_revision(home, socket.gethostname())])
        self.assertEqual(release.select(INVENTORY, known)[0], ['desktop', 'fleet', 'law', 'mail'])
        release.home_receipt(home).unlink()
        unknown = release.changed(self.repo, self.candidate,
            [self.base, release.home_revision(home, socket.gethostname())])
        self.assertEqual(release.select(INVENTORY, unknown)[0], sorted(INVENTORY))


class HomeProvenance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.pointer = self.home / '.local/state/home-manager/gcroots/current-home'
        self.pointer.parent.mkdir(parents=True)
        self.output = self.home / 'generation'
        self.output.mkdir()
        self.candidate = 'a' * 40
        self.target = socket.gethostname()

    def activator(self, *, fail=False, wrong=False):
        script = self.output / 'activate'
        script.write_text(f'#!{sys.executable}\nfrom pathlib import Path\n'
            f'p = Path({str(self.pointer)!r})\np.unlink(missing_ok=True)\n'
            f'p.symlink_to({str(self.home if wrong else self.output)!r})\n'
            f'raise SystemExit({19 if fail else 0})\n')
        script.chmod(0o700)

    def current(self):
        return release.home_revision(self.home, self.target)

    def test_success_uses_actual_generation_and_invalidates_on_change(self):
        self.assertIsNone(self.current())
        self.activator()
        release.activate_home(str(self.output), self.candidate, self.target, self.home)
        self.assertEqual(self.current(), self.candidate)
        profile = self.home / '.local/state/nix/profiles/home-manager'
        profile.parent.mkdir(parents=True)
        profile.symlink_to(self.output)
        self.assertIsNone(self.current())
        release.activate_home(str(self.output), self.candidate, self.target, self.home)
        self.assertEqual(self.current(), self.candidate)
        self.pointer.unlink()
        self.pointer.symlink_to(self.home)
        self.assertIsNone(self.current())

    def test_failed_activation_even_same_generation_drops_receipt(self):
        self.activator()
        release.activate_home(str(self.output), self.candidate, self.target, self.home)
        self.activator(fail=True)
        with self.assertRaises(subprocess.CalledProcessError):
            release.activate_home(str(self.output), self.candidate, self.target, self.home)
        self.assertIsNone(self.current())

    def test_success_with_wrong_pointer_cannot_publish(self):
        self.activator(wrong=True)
        with self.assertRaises(ValueError):
            release.activate_home(str(self.output), self.candidate, self.target, self.home)
        self.assertIsNone(self.current())

    def test_bad_receipts_are_unknown(self):
        self.activator()
        release.activate_home(str(self.output), self.candidate, self.target, self.home)
        path = release.home_receipt(self.home)
        valid = json.loads(path.read_text())
        variants = [dict(valid, schemaVersion=2), dict(valid, target='foreign'),
                    dict(valid, revision='HEAD'), dict(valid, lane='system')]
        for data in variants:
            path.write_text(json.dumps(data))
            self.assertIsNone(self.current())
        for text in ('bad json', 'x' * 4097, '[]'):
            path.write_text(text)
            self.assertIsNone(self.current())


if __name__ == '__main__':
    unittest.main()
