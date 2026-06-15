# domains/home/keymap/parts/to-workbench.nix
#
# grammar -> WORKBENCH_KEYMAP JSON (env var, mirroring WORKBENCH_PALETTE).
#
# The host already has a real chord state machine (src/workbench/core/keymap.py)
# but its grammar is hard-coded (LEADER, VERB_PREFIXES) and it currently owns the
# inter-app jumps via Space (which only work from the host pane). Two app-side
# changes (staged) make this live:
#   1. read WORKBENCH_KEYMAP -> feed Keymap.from_actions(globals_=…) so the host
#      speaks the same Space grammar as every other app;
#   2. DROP the Space t/c/m app-jumps — those move to the zellij meta layer
#      (Alt+Space), so the host's Space is purely intra-app (hub list, palette).
#
# The meta map is included for reference/help-rendering only; the host does NOT
# bind it (zellij owns Alt+Space). This generator is ready now.
#
# Pure function: returns { json = "<json>"; }.

{ lib, grammar }:

let
  json = builtins.toJSON {
    leader     = grammar.leader;
    metaLeader = grammar.metaLeader;          # for the host's help overlay only
    groups     = grammar.groups;
    shared     = map (b: { keys = b.keys; desc = b.desc; }) grammar.shared;
    meta       = grammar.meta;                # rendered in help; bound by zellij
  };
in
{ inherit json; }
