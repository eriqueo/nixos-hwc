{ lib, pkgs, repoRoot }:
let
  keymapGrammar = import (repoRoot + "/domains/home/keymap/grammar.nix") { inherit lib; };
  keymapValidator = pkgs.writeText "keymap-validator.py" ''
          import json, pathlib, sys, tomllib

          def validate(chords, groups, space=False, legacy_help=False):
              seen = set()
              for chord in chords:
                  chord = tuple(chord)
                  assert chord and all(chord), f"empty chord: {chord}"
                  assert chord not in seen, f"duplicate chord: {chord}"
                  seen.add(chord)
                  if not space or chord[0] == "<Space>":
                      offset = 1 if space else 0
                      if not (legacy_help and chord == ("?",)):
                          assert len(chord) > offset and chord[offset] in groups, f"unknown group: {chord}"
              for chord in seen:
                  for length in range(1, len(chord)):
                      assert chord[:length] not in seen, f"prefix: {chord[:length]} shadows {chord}"

          def grammar_contexts(grammar):
              apps = set(grammar.get("apps", {})) | set(grammar.get("major", {}))
              apps |= {app for row in grammar["shared"] for app in row.get("cmd", {})}
              for app in sorted(apps - {"aerc"}):
                  rows = [r for r in grammar["shared"] if app in r.get("cmd", {})]
                  rows += grammar.get("apps", {}).get(app, [])
                  chords = [r["keys"].split(" ") for r in rows]
                  major = grammar.get("major", {}).get(app, [])
                  if isinstance(major, list):
                      chords += [["m"] + r["keys"].split(" ") for r in major]
                  yield app, chords
              # Use the production adapter's context selection, including global rows.
              for context, scopes in {
                  "messages": {"global", "account", "message"},
                  "view": {"global", "account", "message", "view", "closable"},
                  "terminal": {"global", "closable"},
              }.items():
                  yield "aerc/" + context, [r["keys"].split(" ") for r in grammar["aerc"]["bindings"]
                                             if r["scope"] in scopes]

          def self_test(groups):
              for fixture in ([["invalid", "x"]], [["g", "x"], ["g", "x"]],
                              [["g", "x"], ["g", "x", "y"]]):
                  try:
                      validate(fixture, groups)
                  except AssertionError:
                      pass
                  else:
                      raise AssertionError(f"invalid fixture accepted: {fixture}")
              validate([["g", "x"], ["f", "x"]], groups)
              for fixture in ([["<Space>", "invalid", "x"]], [["y"], ["y", "y"]],
                              [["j"], ["j"]]):
                  try:
                      validate(fixture, groups, space=True)
                  except AssertionError:
                      pass
                  else:
                      raise AssertionError(f"invalid TOML chord fixture accepted: {fixture}")
              print("seeded group, duplicate and prefix violations rejected")

          grammar = json.loads(pathlib.Path(sys.argv[1]).read_text())
          groups = grammar["groups"]
          self_test(groups)
          if len(sys.argv) == 2:
              # Check declarations even when a row has no current consumer.
              for row in grammar["shared"] + [r for rows in grammar.get("apps", {}).values() for r in rows]:
                  validate([row["keys"].split(" ")], groups)
              for context, chords in grammar_contexts(grammar):
                  try:
                      # Aerc's existing Space ? help is explicitly outside its group table
                      # (to-aerc excludes it from activeGroups). Keep it until regrouping.
                      validate(chords, groups, legacy_help=context.startswith("aerc/"))
                  except AssertionError as error:
                      raise AssertionError(f"{context}: {error}") from error
                  print(f"{context}: {len(chords)} grammar chords pass")
          else:
              data = tomllib.loads(pathlib.Path(sys.argv[2]).read_text())
              for context, section in data.items():
                  chords = [r["on"] for field in ("prepend_keymap", "keymap", "append_keymap")
                            for r in section.get(field, [])]
                  validate(chords, groups, space=True)
                  assert all("run" in r for r in section.get("prepend_keymap", [])), context
                  print(f"{context}: {len(chords)} TOML chords pass")
              # A grammar command must survive the actual Home Manager wiring.
              expected = {tuple(["<Space>"] + r["keys"].split(" "))
                          for r in grammar["shared"] + grammar.get("apps", {}).get("yazi", [])
                          if "yazi" in r.get("cmd", {})}
              actual = {tuple(r["on"]) for r in data["mgr"]["prepend_keymap"] if r["on"][0] == "<Space>"}
              assert actual == expected, f"Space wiring mismatch: missing {expected - actual}, extra {actual - expected}"
              manager = data["mgr"]["prepend_keymap"]
              space_commands = {r["run"] for r in manager if r["on"][0] == "<Space>"}
              native_commands = {r["run"] for r in manager if r["on"][0] != "<Space>"}
              assert native_commands <= space_commands, f"manager actions without Space path: {native_commands - space_commands}"
        '';
  keymapGrammarFile = pkgs.writeText "keymap-grammar.json" (builtins.toJSON keymapGrammar);
in { inherit keymapGrammar keymapValidator keymapGrammarFile; }
