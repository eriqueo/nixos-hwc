"""Production-entry regressions; stream-session.py remains the runtime helper.

The sibling index.nix owns declarative wiring, not a Python process test harness.
"""
import fcntl
import importlib.util
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('session', Path(__file__).with_name('stream-session.py'))
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SessionTests(unittest.TestCase):
    def test_busy_game_rejects_before_media_or_child_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            with (base / 'game.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with patch.object(session, 'BASE', base), \
                     patch.object(session, 'catalog') as catalog, \
                     patch.object(session, 'playable_image') as image, \
                     patch.object(session, 'game_process') as child:
                    self.assertEqual(session.game(), 2)
                    catalog.assert_not_called()
                    image.assert_not_called()
                    child.assert_not_called()

    def test_lock_is_released_after_foreground_game(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            entry = {'system': 'ps2', 'path': base / 'game.iso'}
            with patch.object(session, 'BASE', base), \
                 patch.object(session, 'RUNTIME', base), \
                 patch.object(session, 'catalog', return_value={'example': entry}), \
                 patch.object(session, 'playable_image', return_value=entry['path']), \
                 patch.object(session, 'game_process', return_value=0) as child, \
                 patch.object(sys, 'argv', ['session', 'game', 'example']):
                self.assertEqual(session.game(), 0)
                child.assert_called_once()
            with (base / 'game.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_run_waits_before_spawning_any_session_process(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name in ['credentials.json', 'server-key.pem', 'server-cert.pem']:
                (base / name).touch()
            config = base / 'sunshine.conf'
            config.write_text('bind_address = 192.0.2.1\nport = 47989\n')
            with patch.object(session, 'BASE', base), \
                 patch.object(session, 'wait_for_address', side_effect=RuntimeError('ADDRESS_NOT_READY')) as wait, \
                 patch.object(session.subprocess, 'Popen') as spawn, \
                 patch.object(sys, 'argv', ['session', 'run', str(config)]):
                with self.assertRaisesRegex(RuntimeError, 'ADDRESS_NOT_READY'):
                    session.run()
                wait.assert_called_once()
                spawn.assert_not_called()

    def test_listener_probe_uses_real_tcp_connection(self):
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            session.wait_for_listener('127.0.0.1', server.getsockname()[1], [], timeout=0.2)
            connection, _ = server.accept()
            connection.close()
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1', 0))  # Reserved but deliberately not listening.
            with self.assertRaisesRegex(RuntimeError, 'STREAM_LISTENER_TIMEOUT'):
                session.wait_for_listener('127.0.0.1', reserved.getsockname()[1], [], timeout=0.05)

    def test_dead_child_cannot_report_ready(self):
        with self.assertRaisesRegex(RuntimeError, 'STREAM_CHILD_EXITED'):
            session.wait_for_listener('127.0.0.1', 1, [Mock(poll=lambda: 1)], timeout=0.2)

    def test_run_does_not_notify_before_actual_listener(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name in ['credentials.json', 'server-key.pem', 'server-cert.pem', 'pulse.socket']:
                (base / name).touch()
            config = base / 'sunshine.conf'
            config.write_text('bind_address = 127.0.0.1\nport = 47989\n')
            names = [base / 'keyboard', base / 'mouse']
            for path, name in zip(names, ['Keyboard passthrough', 'Mouse passthrough']):
                path.write_text(name)
            actual_exists = Path.exists
            actual_glob = Path.glob
            display_checks = iter([False, True])
            def exists(path):
                return next(display_checks) if str(path) == '/tmp/.X11-unix/X95' else actual_exists(path)
            def glob(path, pattern):
                return names if str(path) == '/sys/class/input' else actual_glob(path, pattern)
            child = Mock(poll=lambda: None, wait=lambda timeout: 0)
            with patch.object(session, 'BASE', base), patch.object(session, 'RUNTIME', base), \
                 patch.object(session, 'catalog', return_value={}), \
                 patch.object(session, 'prepare_controllers'), \
                 patch.object(session, 'wait_for_address'), \
                 patch.object(session, 'wait_for_listener', side_effect=RuntimeError('STREAM_NOT_READY')) as listener, \
                 patch.object(session, 'notify_ready', side_effect=RuntimeError('UNEXPECTED_READY')) as notify, \
                 patch.object(session.subprocess, 'Popen', return_value=child), \
                 patch.object(Path, 'exists', exists), patch.object(Path, 'glob', glob), \
                 patch.object(sys, 'argv', ['session', 'run', str(config)]):
                with self.assertRaisesRegex(RuntimeError, 'STREAM_NOT_READY'):
                    session.run()
                listener.assert_called_once()
                notify.assert_not_called()


if __name__ == '__main__':
    unittest.main()
