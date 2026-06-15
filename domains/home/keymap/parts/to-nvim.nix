# domains/home/keymap/parts/to-nvim.nix
#
# grammar -> Neovim lua for the Space MNEMONIC LAYER ONLY. nvim's motions,
# LSP-on-attach, and plugin config stay hand-written lua in
# apps/nvim/parts/lua/**; this generator owns only the `<leader>…` grammar +
# which-key group registration (so the popup also labels the groups). Source
# this lua AFTER mapleader is set.
#
# Pure function: returns { lua = "<lua>"; }.

{ lib, grammar }:

let
  app = "nvim";

  # "g h" -> "<leader>gh"   (mapleader = " ")
  lhs = keys: "<leader>" + lib.concatStrings (lib.splitString " " keys);

  esc = s: lib.replaceStrings [ ''"'' ] [ ''\"'' ] s;

  sharedFor = lib.filter (b: (b.cmd or {}) ? ${app}) grammar.shared;
  mapLine = b:
    ''vim.keymap.set("n", "${lhs b.keys}", "${esc b.cmd.${app}}", { desc = "${esc b.desc}", silent = true })'';

  majorLine = m:
    ''vim.keymap.set("n", "<leader>m${m.keys}", "${esc (m.cmd or "")}", { desc = "${esc m.desc}", silent = true })'';

  # which-key group labels so the popup names the groups (g=go, f=search, …)
  groupRegister = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: name:
    ''  ok, wk = pcall(require, "which-key"); if ok then wk.add({ { "<leader>${k}", group = "${name}" } }) end''
  ) grammar.groups);

  lua = lib.concatStringsSep "\n" (
    [ "-- generated Space grammar (domains/home/keymap/grammar.nix)" ]
    ++ (map mapLine sharedFor)
    ++ (map majorLine (grammar.major.${app} or []))
    ++ [ "-- which-key group labels" groupRegister ]
  );
in
{ inherit lua; }
