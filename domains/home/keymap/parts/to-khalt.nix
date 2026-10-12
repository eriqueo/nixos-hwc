# Grammar rows -> shared schema-1 leader file. Bare aliases stay native.
{ lib, grammar }:
let
  rows = grammar.apps.khalt;
  bindings = builtins.listToAttrs (map (r: { name = r.keys; value = r.cmd.khalt; }) rows);
  json = builtins.toJSON {
    schemaVersion = 1;
    groups = lib.filterAttrs (key: _: lib.any (r: builtins.head (lib.splitString " " r.keys) == key) rows) grammar.groups;
    inherit bindings;
  };
  keybindingsBlock = "[keybindings]\n"
    + lib.concatMapStrings (r: "${lib.removePrefix "key:" r.cmd.khalt} = ${lib.concatStringsSep ", " r.bare}\n")
        (lib.filter (r: r ? bare) rows)
    + "leader = ' '\n";
in { inherit keybindingsBlock; leaderTree = json; }
