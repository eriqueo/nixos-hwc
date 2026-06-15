# domains/home/keymap/parts/to-aerc.nix
#
# grammar -> aerc binds.conf fragment for the Space grammar. aerc is already the
# model: its `<Space>g…` (folders) and `<Space>m…` (tags) come from
# domains/mail/aerc/parts/tags.nix and stay there — this generator owns the
# REST of the shared Space grammar (search under f, sort under s, toggles) and
# COMPOSES with the tag-generated blocks; it never duplicates them.
#
# Pure function: returns { bindsFragment = "<lines>"; } to splice under the
# [messages] context in binds.nix.

{ lib, grammar }:

let
  app = "aerc";

  # "f g" -> "<Space>fg"
  lhs = keys: "<Space>" + lib.concatStrings (lib.splitString " " keys);

  sharedFor = lib.filter (b: (b.cmd or {}) ? ${app}) grammar.shared;
  line = b: ''      ${lhs b.keys} = ${b.cmd.${app}}<Enter>'';

  bindsFragment = lib.concatStringsSep "\n" (
    [ "      # --- generated Space grammar (domains/home/keymap/grammar.nix);"
      "      #     <Space>g (folders) + <Space>m (tags) come from tags.nix ---" ]
    ++ (map line sharedFor)
  );
in
{ inherit bindsFragment; }
