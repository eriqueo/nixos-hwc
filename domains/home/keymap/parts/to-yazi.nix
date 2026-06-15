# domains/home/keymap/parts/to-yazi.nix
#
# grammar -> yazi keymap.toml [mgr] prepend_keymap fragment (the Space mnemonic
# layer ONLY). yazi's bare keys + motions stay in apps/yazi/parts/keymap.nix;
# this generator owns just the `<Space> …` grammar so editing grammar.nix
# re-keys yazi's leader menu. Compose: append `.keymapFragment` inside the
# existing `[mgr]` prepend_keymap array.
#
# Pure function: returns { keymapFragment = "<toml lines>"; }.

{ lib, grammar }:

let
  app = "yazi";

  # "g h" -> on = [ "<Space>", "g", "h" ]
  onArray = keys:
    let toks = lib.splitString " " keys;
    in "[ " + lib.concatStringsSep ", " (map (t: ''"${t}"'') ([ "<Space>" ] ++ toks)) + " ]";

  sharedFor = lib.filter (b: (b.cmd or {}) ? ${app}) grammar.shared;

  line = b: ''  { on = ${onArray b.keys}, run = "${b.cmd.${app}}", desc = "${b.desc}" },'';

  majorLines = lib.concatStringsSep "\n" (map (m:
    ''  { on = [ "<Space>", "m", "${m.keys}" ], desc = "${m.desc}" },''
  ) (grammar.major.${app} or []));

  keymapFragment = lib.concatStringsSep "\n" (
    [ "  # --- generated Space grammar (domains/home/keymap/grammar.nix) ---" ]
    ++ (map line sharedFor)
    ++ [ majorLines ]
  );
in
{ inherit keymapFragment; }
