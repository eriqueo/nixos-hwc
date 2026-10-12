# Grammar rows -> shared schema-1 leader file. Bare aliases stay native.
{ lib, grammar }:
let
  rows = grammar.apps.todui;
  bindings = builtins.listToAttrs (map (r: { name = r.keys; value = r.cmd.todui; }) rows);
  json = builtins.toJSON {
    schemaVersion = 1;
    groups = lib.filterAttrs (key: _: lib.any (r: builtins.head (lib.splitString " " r.keys) == key) rows) grammar.groups;
    inherit bindings;
  };
in { inherit json; }
