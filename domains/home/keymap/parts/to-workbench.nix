# domains/home/keymap/parts/to-workbench.nix
#
# grammar -> versioned Workbench keymap JSON.
#
# Only shared rows that explicitly declare ``cmd.workbench`` participate. This
# keeps the intent vocabulary owned by grammar.nix and prevents the adapter from
# guessing how another app's native command should map into Workbench.
#
# Pure function: returns { json = "<json>"; }.

{ lib, grammar }:

let
  json = builtins.toJSON {
    schemaVersion = 1;
    bindings = map (binding: {
      chord = binding.keys;
      intent = binding.cmd.workbench;
      description = binding.desc;
    }) (lib.filter (binding: binding.cmd ? workbench) grammar.shared);
  };
in
{ inherit json; }
