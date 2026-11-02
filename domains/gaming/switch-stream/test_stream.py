"""Regressions at the real game, migration, client and boot entry points.

stream.py owns runtime behavior; this sibling exercises effects with private fixtures.
"""
import ast
import configparser
import importlib.util
import json
from pathlib import Path
import subprocess
import socket
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('stream', Path(__file__).with_name('stream.py'))
stream = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stream)


class StreamTests(unittest.TestCase):
    def test_prepare_wires_handheld_and_meta_input_without_touching_other_state(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'qt-config.ini'
            config.write_text('[Unrelated]\nprivate=@ByteArray(retain\\value)\n[UI]\nPaths\\gamedirs\\size=1\nPaths\\gamedirs\\1\\path=/old\n')
            cfg = {'edenConfig': str(config), 'gameRoot': '/new/root'}
            with patch.object(stream, 'eden_running', return_value=False):
                stream.prepare_eden(cfg)
                first = config.read_bytes()
                stream.prepare_eden(cfg)
            self.assertEqual(config.read_bytes(), first)
            ini = configparser.ConfigParser(interpolation=None); ini.optionxform = str; ini.read(config)
            self.assertEqual(ini['Controls']['player_8_connected'], 'true')
            self.assertEqual(ini['Controls']['player_0_connected'], 'false')
            self.assertEqual(ini['Controls']['player_8_type'], '4')
            for slot in [0, 8]:
                self.assertIn('button:1', ini['Controls'][f'player_{slot}_button_a'])
                self.assertIn('hat:0,direction:up', ini['Controls'][f'player_{slot}_button_dup'])
                self.assertIn('axis_x:0,axis_y:1', ini['Controls'][f'player_{slot}_lstick'])
            self.assertEqual(ini['System']['use_docked_mode'], '0')
            self.assertEqual(ini['UI']['Paths\\gamedirs\\size'], '2')
            self.assertEqual(ini['UI']['Paths\\gamedirs\\1\\path'], '/old')
            self.assertIn('private=@ByteArray(retain\\value)', config.read_text())
            self.assertEqual(ini['UI']['Shortcuts\\Main%20Window\\Stop%20Emulation\\Controller_KeySeq'], 'L+Plus+Minus')

    def test_game_rejects_live_eden_before_config_or_launch_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(stream, 'eden_running', return_value=True), \
                 patch.object(stream, 'merge_file') as merge, patch.object(stream.subprocess, 'Popen') as spawn:
                with self.assertRaisesRegex(RuntimeError, 'EDEN_BUSY'):
                    stream.game({'state': directory}, 'library')
                merge.assert_not_called(); spawn.assert_not_called()

    def test_private_pairing_migration_is_repeatable_and_conflict_preserves_all_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / 'source'; source.mkdir()
            target = root / 'target'
            for name in ['state.json', 'key.pem', 'cert.pem']:
                (source / name).write_text(name)
            cfg = {'state': str(target)}
            stream.migrate(cfg, source); stream.migrate(cfg, source)
            for file in source.iterdir():
                self.assertEqual(file.read_bytes(), (target / file.name).read_bytes())
                self.assertEqual((target / file.name).stat().st_mode & 0o777, 0o600)
            (source / 'cert.pem').write_text('another identity')
            before = {p.name: p.read_bytes() for p in target.iterdir()}
            with self.assertRaisesRegex(RuntimeError, 'PAIRING_IDENTITY_CONFLICT'):
                stream.migrate(cfg, source)
            self.assertEqual({p.name: p.read_bytes() for p in target.iterdir()}, before)

    def test_pi_install_preserves_hosts_and_does_not_change_live_client_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); moonlight = root / 'Moonlight.conf'
            original = '[General]\ngamepadmouse=false\nswapfacebuttons=true\n[hosts]\n1\\manualaddress=home\n1\\srvcert=@ByteArray(private)\n'
            moonlight.write_text(original)
            real_atomic = stream.atomic
            writes = {}
            def atomic(path, data, mode=0o600):
                writes[str(path)] = data
                return False
            cfg = {'games': [{'id': 'pikachu', 'title': "Pokémon Let's Go Pikachu"}]}
            with patch.object(stream, 'MOONLIGHT', moonlight), patch.object(stream, 'atomic', side_effect=atomic), \
                 patch.object(stream, 'call') as call, patch.object(stream, 'moonlight_running', return_value=True):
                stream.pi_install(cfg, root / 'config.json')
            self.assertEqual(moonlight.read_text(), original)
            self.assertTrue(any('ports/Switch - pikachu.sh' in p for p in writes))
            call.assert_called_once_with(['batocera-services', 'enable', 'switch_stream'])
            moonlight.write_text(original.replace('gamepadmouse=false', 'gamepadmouse=true'))
            with self.assertRaisesRegex(RuntimeError, 'CONFIG_BUSY'):
                stream.merge_file(moonlight, {'General': stream.PREFS}, may_change=False)

    def test_bluetooth_guard_skips_disconnected_audio_without_forking_unknown_versions(self):
        source = 'def refresh_audio_on_connect(properties):\n  probes.append(properties)\n'
        with patch.object(stream, 'FACTORY_AGENT_SHA', stream.hashlib.sha256(source.encode()).hexdigest()):
            patched = stream.patched_agent(source)
            self.assertEqual(stream.patched_agent(patched), patched)
        namespace = {'probes': []}; exec(patched, namespace)
        namespace['refresh_audio_on_connect']({'Connected': False})
        self.assertEqual(namespace['probes'], [])
        namespace['refresh_audio_on_connect']({'Connected': True})
        self.assertEqual(len(namespace['probes']), 1)
        with self.assertRaisesRegex(RuntimeError, 'BLUETOOTH_AGENT_UNSUPPORTED'):
            stream.patched_agent(source + '# upgraded\n')

    def test_host_refuses_to_take_over_active_game(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['state.json', 'key.pem', 'cert.pem']:
                (root / name).touch()
            with patch.object(stream, 'eden_running', return_value=True), patch.object(stream.subprocess, 'Popen') as spawn:
                with self.assertRaisesRegex(RuntimeError, 'TRIAL_ACTIVE'):
                    stream.host_run({'state': directory}, '/not/read')
                spawn.assert_not_called()

    def test_stream_launch_uses_working_quality_and_no_overlay(self):
        cfg = {'host': '192.0.2.1', 'games': [{'id': 'pikachu', 'title': "Pokémon Let's Go Pikachu"}]}
        with patch.object(stream, 'moonlight_running', return_value=False), patch.object(stream, 'pi_start'), \
             patch.object(stream, 'merge_file'), patch.object(stream.os, 'execvp') as execvp:
            stream.pi_stream(cfg, 'pikachu')
        args = execvp.call_args.args[1]
        self.assertIn('HEVC', args); self.assertIn('--720', args)
        self.assertNotIn('--performance-overlay', args)
        self.assertEqual(args[-2:], ['192.0.2.1', "Pokémon Let's Go Pikachu"])

    def test_client_boot_reuses_existing_audio_sink_and_agent(self):
        def call(args, **kwargs):
            if args == ['pactl', 'list', 'short', 'sinks']:
                return '1157 tv_hdmi PipeWire s32le 2ch 48000Hz RUNNING'
            if args == ['pactl', 'get-default-sink']:
                return 'tv_hdmi'
            if args == ['wlr-randr']:
                return 'HDMI-A-1'
            return 'ready'
        with patch.object(Path, 'read_text', return_value='factory'), \
             patch.object(stream, 'patched_agent', return_value='already patched'), \
             patch.object(stream, 'atomic', return_value=False), patch.object(stream, 'call', side_effect=call) as calls:
            result = stream.pi_start_locked({})
        self.assertEqual(result['state'], 'ready')
        commands = [c.args[0] for c in calls.call_args_list]
        self.assertIn(['wlr-randr', '--output', 'HDMI-A-1', '--mode', '1920x1080@60Hz'], commands)
        self.assertIn(['btmgmt', 'connectable', 'on'], commands)
        self.assertFalse(any('load-module' in command or 'start-stop-daemon' in command for command in commands))

    def test_readiness_requires_real_listener(self):
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0)); server.listen()
            port = server.getsockname()[1]
            stream.wait_ready(lambda: stream.listener('127.0.0.1', port), timeout=0.1)
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1', 0))
            with self.assertRaisesRegex(RuntimeError, 'STREAM_PREREQUISITE_TIMEOUT'):
                stream.wait_ready(lambda: stream.listener('127.0.0.1', reserved.getsockname()[1]), timeout=0.01)


if __name__ == '__main__':
    unittest.main()
