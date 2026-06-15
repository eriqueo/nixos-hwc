# domains/home/keymap/parts/to-khalt.nix
#
# grammar -> khalt config. Two outputs:
#   * keybindingsBlock : a khal `[keybindings]` override (leaf keys khalt's
#     config CAN drive today) — appended via khalt's `extraConfig` hook.
#   * leaderTree       : JSON of the Space-menu group structure for the fork.
#     khalt's build_keymap() currently hard-codes the menu TREE in Python
#     (khal/ui/khalt_leader.py); to fully drive the GROUPS from here it must be
#     taught to read this JSON (KHALT_LEADER_TREE). Until then khalt expresses a
#     documented SUBSET (the leaf keys) and the tree stays its built-in default.
#     See spec §2.4 (per-app capability limits).
#
# Pure function: returns { keybindingsBlock = "<ini>"; leaderTree = "<json>"; }.

{ lib, grammar }:

let
  # list-app bare verbs khalt shares with todui (a=add, e=edit, d=delete, Enter=open)
  verb = name: lib.findFirst (v: v.intent == name) null grammar.listVerbs;
  keyOf = name: let v = verb name; in if v == null then "" else v.key;

  # khal's [keybindings] uses comma-lists of keys per command. We map the shared
  # verbs onto khal's command names; export/duplicate move under the leader menu.
  keybindingsBlock = ''
    [keybindings]
    # generated from domains/home/keymap/grammar.nix (list-app verbs)
    new = ${keyOf "add"}
    delete = ${keyOf "delete"}
    # edit/open keep Enter; khalt also accepts ${keyOf "edit"} for edit via the leader
    leader = ' '
  '';

  # The leader-tree the fork should consume (KHALT_LEADER_TREE) once parameterized.
  leaderTree = builtins.toJSON {
    leader = grammar.leader;
    groups = grammar.groups;
    major  = map (m: { key = m.keys; desc = m.desc; }) (grammar.major.khalt or []);
    verbs  = grammar.listVerbs;
  };
in
{ inherit keybindingsBlock leaderTree; }
