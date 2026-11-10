"""Run the shared copier against disposable source, destination and state trees.

The existing checks.nix owns Nix assembly checks; these fixtures drive the Python
CLI and its copy/scan interface without touching the running media library.
"""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(sys.argv[1]).resolve()
sys.argv = [sys.argv[0]]
spec = importlib.util.spec_from_file_location("copier", SOURCE)
copier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(copier)


class CopyContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "downloads"
        self.destination = self.root / "library"
        self.state = self.root / "state"
        self.source.mkdir()
        self.book = self.source / "Book"
        self.book.mkdir()
        (self.book / "chapter.mp3").write_text("seeded audio")
        self.env = {
            "PATH": os.environ["PATH"], "SOURCE_DIR": str(self.source),
            "DEST_DIR": str(self.destination), "STATE_DIR": str(self.state),
            "AUDIOBOOKSHELF_URL": "http://127.0.0.1:1",
            "AUDIOBOOKSHELF_API_KEY": "", "TRIGGER_LIBRARY_SCAN": "0",
        }

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SOURCE), *map(str, args)],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def configuration(self):
        with patch.dict(os.environ, self.env, clear=True):
            return copier.Config()

    def test_cli_copies_once_preserves_seeding_and_existing_library(self):
        target = self.destination / self.book.name
        target.mkdir(parents=True)
        (target / "chapter.mp3").write_text("existing library")
        (self.book / "new.mp3").write_text("new chapter")
        first = self.cli("--scan-all")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual((target / "chapter.mp3").read_text(), "existing library")
        self.assertEqual((target / "new.mp3").read_text(), "new chapter")
        self.assertEqual((self.book / "chapter.mp3").read_text(), "seeded audio")
        marker = (self.book / ".abs-copied").read_bytes()
        second = self.cli("--scan-all")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.book / ".abs-copied").read_bytes(), marker)
        state = json.loads((self.state / "state.json").read_text())
        self.assertEqual(set(state["processed"]), {str(self.book)})

    def test_legacy_empty_marker_remains_a_completed_copy(self):
        (self.book / ".abs-copied").touch()
        result = self.cli("--scan-all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.destination / self.book.name).exists())

    def test_dry_run_writes_no_state_or_markers_and_makes_no_scan(self):
        config = self.configuration()
        config.dry_run = True
        config.audiobookshelf_api_key = "fixture"
        config.trigger_library_scan = True
        state = copier.StateManager(config.state_file)
        with patch.object(copier.requests, "get") as get, patch.object(copier.requests, "post") as post:
            self.assertEqual(copier.scan_all(config, state), 1)
        get.assert_not_called()
        post.assert_not_called()
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.state.exists())
        self.assertFalse((self.book / ".abs-copied").exists())

    def test_extension_configuration_reaches_the_real_scanner(self):
        (self.book / "chapter.mp3").rename(self.book / "chapter.fixture")
        self.assertEqual(self.cli("--scan-all").returncode, 0)
        self.assertFalse((self.destination / self.book.name).exists())
        self.env["AUDIO_EXTENSIONS"] = "fixture"
        result = self.cli("--scan-all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.destination / self.book.name / "chapter.fixture").is_file())

    def test_prior_json_state_and_unknown_fields_survive(self):
        self.state.mkdir()
        before = {"processed": {"old": {"dest": "prior", "timestamp": "retained"}},
                  "last_scan": None, "custom": {"value": 7}}
        (self.state / "state.json").write_text(json.dumps(before))
        result = self.cli("--scan-all")
        self.assertEqual(result.returncode, 0, result.stderr)
        current = json.loads((self.state / "state.json").read_text())
        self.assertEqual(current["processed"]["old"], before["processed"]["old"])
        self.assertEqual(current["custom"], before["custom"])
        self.assertFalse(list(self.state.glob(".state-*")))

    def test_copy_failure_does_not_acknowledge_or_change_prior_state(self):
        config = self.configuration()
        state = copier.StateManager(config.state_file)
        with patch.object(copier.subprocess, "run", return_value=Mock(returncode=1, stderr="fixture", stdout="")):
            self.assertFalse(copier.process_single(self.book, config, state))
        self.assertFalse(config.state_file.exists())
        self.assertFalse((self.book / ".abs-copied").exists())

    def test_competing_hook_and_sweep_refuse_a_second_effect(self):
        with copier.copy_lock(self.state, False):
            result = self.cli("--scan-all")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse((self.destination / self.book.name).exists())
        self.assertFalse((self.state / "state.json").exists())
        self.assertEqual(self.cli("--scan-all").returncode, 0)
        self.assertTrue((self.book / ".abs-copied").exists())

    def test_lock_remains_readable_across_root_and_user_umasks(self):
        prior = os.umask(0o077)
        try:
            with copier.copy_lock(self.state, False):
                self.assertEqual((self.state / ".copy.lock").stat().st_mode & 0o777, 0o644)
        finally:
            os.umask(prior)

    def test_scan_policy_changes_no_copy_decision(self):
        self.destination.mkdir()
        config = self.configuration()
        config.audiobookshelf_api_key = "fixture"
        config.trigger_library_scan = True
        state = copier.StateManager(config.state_file)
        response = Mock()
        response.json.return_value = {"libraries": [{"id": "library", "name": "Books"}]}
        with patch.object(copier.requests, "get", return_value=response), patch.object(copier.requests, "post", return_value=Mock(ok=True)) as post:
            self.assertTrue(copier.process_single(self.book, config, state))
        self.assertEqual(post.call_args.args[0], "http://127.0.0.1:1/api/libraries/library/scan")
        self.assertEqual(post.call_args.kwargs["headers"], {"Authorization": "Bearer fixture"})


unittest.main()
