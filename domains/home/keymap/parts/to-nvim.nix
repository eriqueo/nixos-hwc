# Space leader maps and which-key labels have one producer: grammar.nix.
{ lib, grammar }:
let
  rows = lib.filter (row: (row.cmd or {}) ? nvim)
    (grammar.shared ++ (grammar.apps.nvim or []));
  quote = builtins.toJSON;
  chord = row: "<leader>" + lib.concatStrings (lib.splitString " " row.keys);
  mapLine = row:
    "vim.keymap.set(" + ("{ " + lib.concatStringsSep ", " (map quote (row.nvim.mode or [ "n" ])) + " }") + ", " + quote (chord row) + ", "
    + (if row.nvim.lua or false then row.cmd.nvim else quote row.cmd.nvim)
    + ", { desc = " + quote row.desc + ", silent = true })";
  groups = lib.mapAttrsToList (key: name:
    "{ " + quote ("<leader>" + key) + ", group = " + quote name + " }") grammar.groups;
in {
  inherit rows;
  lua = lib.concatStringsSep "\n" ([
    "-- Generated from domains/home/keymap/grammar.nix."
  ] ++ map mapLine rows ++ [
    "local wk = require(\"which-key\")"
    ("wk.add({ " + lib.concatStringsSep ", " groups + " })")
  ]);
}
