"""Favorites store contracts and real-Yazi acceptance through evaluated HM config.

python test.py --config-json /tmp/yazi-favorites-config.json
The test owns a private tmux server and temporary data, never the user's sessions.
store.py is the production adapter; main.lua owns UI/input, so neither hosts tests.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import store

PLUGIN = Path(__file__).resolve().parent
CONFIG = None
BREAK_WIRING = False
INSTALLED = False


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yazi-store-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / "data" / "favorites.json"
        self.defaults = self.root / "defaults.json"
        self.defaults.write_text(json.dumps({"version": 1, "favorites": []}))
        self.folder = self.root / "folder with spaces"
        self.folder.mkdir()

    def run_action(self, action, path=None, name="Favorite"):
        return store.run(self.path, self.defaults, action, str(path or self.folder), name)

    def test_crud_survives_reload_and_repeated_effects(self):
        self.run_action("add", name="Résumé")
        self.run_action("add", name="Duplicate")
        self.assertEqual(len(self.run_action("load")["favorites"]), 1)
        self.run_action("rename", name="Renamed")
        self.assertEqual(self.run_action("load")["favorites"][0]["name"], "Renamed")
        self.run_action("remove")
        self.run_action("remove")
        self.assertEqual(self.run_action("load")["favorites"], [])
        self.assertTrue(self.folder.is_dir())

    def test_corruption_and_capacity_preserve_original(self):
        self.path.parent.mkdir()
        for raw in [b"not json", b'{"version":2,"favorites":[]}', b" " * (store.MAX_BYTES + 1)]:
            self.path.write_bytes(raw)
            with self.assertRaises(store.StoreError):
                self.run_action("add")
            self.assertEqual(self.path.read_bytes(), raw)
        self.path.write_text(json.dumps({"version": 1, "favorites": [
            {"name": str(i), "path": f"/fixture/{i}"} for i in range(store.MAX_ENTRIES)
        ]}))
        original = self.path.read_bytes()
        with self.assertRaises(store.StoreError):
            self.run_action("add")
        self.assertEqual(self.path.read_bytes(), original)

    def test_atomic_failure_and_busy_writer_preserve_data(self):
        self.run_action("add")
        original = self.path.read_bytes()
        with patch.object(store.os, "replace", side_effect=OSError("injected rename failure")):
            with self.assertRaises(OSError):
                self.run_action("rename", name="Lost")
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(self.path.parent.glob(".favorites-*")), [])
        with self.path.with_suffix(".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(store.StoreError) as caught:
                self.run_action("remove")
            self.assertEqual(caught.exception.code, "busy")
        self.assertEqual(self.path.read_bytes(), original)

    def test_parallel_processes_never_overwrite_successful_additions(self):
        folders = [self.root / str(i) for i in range(12)]
        for folder in folders:
            folder.mkdir()
        def add(folder):
            result = subprocess.run([sys.executable, str(PLUGIN / "store.py"), str(self.path),
                                     str(self.defaults), "add", str(folder), folder.name],
                                    capture_output=True, text=True, timeout=5)
            return folder, json.loads(result.stdout)
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(add, folders))
        successful = {str(folder) for folder, result in results if result["ok"]}
        self.assertTrue(successful)
        self.assertEqual({item["path"] for item in self.run_action("load")["favorites"]}, successful)
        for _, result in results:
            self.assertTrue(result["ok"] or result["code"] == "busy")


@unittest.skipUnless(CONFIG, "Pass --config-json to exercise the evaluated production wiring")
class TerminalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="yazi-terminal-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.socket = str(self.root / "tmux.sock")
        self.addCleanup(self.stop_terminal)
        self.first, self.second, self.third = [self.root / name for name in ("first", "second", "third")]
        for folder in (self.first, self.second, self.third):
            folder.mkdir()
            (folder / (folder.name + "-marker.txt")).write_text("fixture")
        self.state = self.root / "favorites.json"
        defaults = self.root / "defaults.json"
        defaults.write_text(json.dumps({"version": 1, "favorites": [
            {"name": "First", "path": str(self.first)},
            {"name": "Second", "path": str(self.second)},
        ]}))
        config = self.root / "config"
        config.mkdir()
        for filename, key in [("yazi.toml", "toml"), ("keymap.toml", "keymap"), ("theme.toml", "theme")]:
            (config / filename).write_text(CONFIG[key])
        plugins = config / "plugins"
        plugins.mkdir()
        for name, source in CONFIG["plugins"].items():
            # Plugin sources may be store paths after evaluation; use the same
            # checkout source so the integration test runs before building it.
            origin = PLUGIN.parent / (name + ".yazi")
            shutil.copytree(source if INSTALLED else (origin if origin.exists() else source), plugins / (name + ".yazi"),
                            ignore=shutil.ignore_patterns("__pycache__"))
        init = CONFIG["init"]
        for key, value in {"python": sys.executable, "helper": str(plugins / "bookmarks.yazi/store.py"),
                           "path": str(self.state), "defaults": str(defaults)}.items():
            init = re.sub(rf"({key}\s*=\s*)\"[^\"]*\"", lambda m: m[1] + json.dumps(value), init, count=1)
        if BREAK_WIRING:
            init = re.sub(r'require\("bookmarks"\):setup \{.*?\n\s*\}\n(?=\s*require\("zoxide"\))', "", init, flags=re.S)
        (config / "init.lua").write_text(init)
        self.tmux("new-session", "-d", "-x", "120", "-y", "30", "-s", "test", "sh")
        self.tmux("set-option", "-g", "remain-on-exit", "on")
        env = {"YAZI_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(self.root / "logs"),
               "_ZO_DATA_DIR": str(self.root / "zoxide")}
        self.command = shlex.join(["env", *(f"{k}={v}" for k, v in env.items()), "yazi",
                                   "--cwd-file", str(self.root / "cwd"), str(self.first)])
        self.tmux("send-keys", "-t", "test", "exec " + self.command, "Enter")
        self.wait_for("First")
        self.wait_for("Second")

    def tmux(self, *arguments, check=True):
        return subprocess.run(["tmux", "-S", self.socket, *arguments],
                              capture_output=True, text=True, check=check, timeout=5).stdout

    def stop_terminal(self):
        pid = self.tmux("display-message", "-p", "-t", "test", "#{pane_pid}", check=False).strip()
        self.tmux("kill-server", check=False)
        deadline = time.monotonic() + 3
        while pid and Path("/proc", pid).exists() and time.monotonic() < deadline:
            time.sleep(0.05)

    def screen(self):
        return self.tmux("capture-pane", "-p", "-t", "test")

    def wait_for(self, text, absent=False):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            screen = self.screen()
            if (text not in screen) if absent else (text in screen):
                return screen
            time.sleep(0.05)
        self.fail(f"Expected {'absence of ' if absent else ''}{text!r}:\n{self.screen()}")

    def keys(self, *keys):
        self.tmux("send-keys", "-t", "test", *keys)

    def test_persistent_sidebar_focus_jump_and_narrow_geometry(self):
        self.wait_for("favorites")
        self.keys("M-j")
        self.wait_for("second-marker.txt")
        self.keys("M-k")
        self.wait_for("first-marker.txt")
        self.keys("M-h")
        self.wait_for("favorites *")
        self.keys("j", "Enter")
        self.wait_for("second-marker.txt")
        self.wait_for("favorites *", absent=True)
        self.keys("M-h")
        self.wait_for("favorites *")
        self.keys("D")  # File deletion must remain blocked while sidebar-focused.
        self.wait_for("Favorites have focus")
        self.wait_for("favorites *")
        self.assertTrue((self.second / "second-marker.txt").exists())
        self.keys("M-l")
        self.wait_for("favorites *", absent=True)
        for width, height in [(60, 18), (32, 8), (120, 30)]:
            self.tmux("resize-window", "-t", "test", "-x", str(width), "-y", str(height))
            self.assertEqual(self.tmux("display-message", "-p", "-t", "test", "#{pane_dead}").strip(), "0")
        self.wait_for("favorites")

    def test_add_rename_remove_restart_and_empty_list(self):
        self.keys("Space", "b", "a")
        self.wait_for("Add current folder")
        self.keys("Enter")
        # Adding an existing favorite is idempotent.
        deadline = time.monotonic() + 5
        while not self.state.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(len(json.loads(self.state.read_text())["favorites"]), 2)
        self.keys("g", "Space")
        self.wait_for("Change directory:")
        self.keys("C-u")
        self.tmux("send-keys", "-l", "-t", "test", str(self.third))
        self.keys("Enter")
        self.wait_for("third-marker.txt")
        self.keys("Space", "b", "a")
        self.wait_for("Add current folder")
        self.keys("Enter")
        self.wait_for("third")
        deadline = time.monotonic() + 5
        while len(json.loads(self.state.read_text())["favorites"]) != 3 and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(len(json.loads(self.state.read_text())["favorites"]), 3)
        self.keys("M-h")
        self.wait_for("favorites *")
        self.keys("r")
        self.wait_for("Rename favorite")
        self.keys("C-u")
        self.tmux("send-keys", "-l", "-t", "test", "Saved Favorite")
        self.keys("Enter")
        self.wait_for("Saved Favorite")
        self.keys("Escape")
        self.wait_for("favorites *", absent=True)
        self.tmux("respawn-pane", "-k", "-t", "test", self.command)
        self.wait_for("Saved Favorite")
        self.keys("M-h")
        self.wait_for("favorites *")
        self.keys("G")
        self.keys("d")
        self.wait_for("Remove favorite?")
        self.keys("y")
        self.wait_for("Saved Favorite", absent=True)
        self.assertTrue((self.third / "third-marker.txt").exists())
        self.keys("Escape")
        self.wait_for("favorites *", absent=True)

        self.state.write_text(json.dumps({"version": 1, "favorites": []}))
        self.tmux("respawn-pane", "-k", "-t", "test", self.command)
        self.wait_for("a: add folder")
        self.keys("M-j", "M-k", "M-h")
        self.wait_for("favorites *")
        self.keys("Escape")
        self.wait_for("favorites *", absent=True)

    def test_fuzzy_finder_and_directory_history(self):
        nested = self.first / "nested"
        nested.mkdir()
        (nested / "needle.txt").write_text("recursive finder fixture")
        self.keys("Z")
        self.wait_for(">")
        self.tmux("send-keys", "-l", "-t", "test", "needle")
        self.wait_for("needle.txt")
        self.keys("Enter")
        self.wait_for(str(nested))
        self.wait_for("favorites")
        self.keys("M-j")
        self.wait_for("second-marker.txt")
        self.keys("z")
        self.wait_for(">")
        self.tmux("send-keys", "-l", "-t", "test", "nested")
        self.wait_for("> nested")
        time.sleep(0.15)  # fzf updates its query and selection on separate ticks.
        self.keys("Enter")
        self.wait_for(str(nested))
        self.wait_for("favorites")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-json", type=Path)
    parser.add_argument("--break-wiring", action="store_true")
    parser.add_argument("--installed", action="store_true")
    arguments, remaining = parser.parse_known_args()
    CONFIG = json.loads(arguments.config_json.read_text()) if arguments.config_json else None
    BREAK_WIRING = arguments.break_wiring
    INSTALLED = arguments.installed
    # skipUnless is evaluated at class definition time.
    TerminalTests.__unittest_skip__ = CONFIG is None
    unittest.main(argv=[sys.argv[0], *remaining])
