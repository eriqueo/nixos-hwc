# Pure grammar -> Yazi manager Space bindings. Native keys stay in the app.
{ lib, grammar, mediaRoot }:
let
  rows = lib.filter (b: (b.cmd or {}) ? yazi)
    (grammar.shared ++ (grammar.apps.yazi or []));
  # JSON strings/arrays are valid TOML values; escape quotes and backslashes once.
  line = b: "      { on = "
    + builtins.toJSON ([ (if grammar.leader == " " then "<Space>" else grammar.leader) ]
      ++ lib.splitString " " b.keys)
    + ", run = " + builtins.toJSON (lib.replaceStrings [ "@mediaRoot@" ] [ mediaRoot ] b.cmd.yazi)
    + ", desc = " + builtins.toJSON b.desc + " },";
in {
  keymapFragment = lib.concatStringsSep "\n" (map line rows);
}
