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
  # verbs onto khal's command names. NOTE: khal has no safe single-key "edit" —
  # editing happens through `view` (Enter shows details, Enter again edits the
  # event). So khalt binds add/delete/open and OMITS the unified `e`=edit
  # (per-app omission rule, grammar.nix §DESIGN); `e` stays khal's native export
  # and `external_edit` (raw .ics in $EDITOR) keeps its `meta E` default — we do
  # NOT put raw-ics edit on a bare key (khal warns that path skips validation).
  keybindingsBlock = ''
    [keybindings]
    # generated from domains/home/keymap/grammar.nix (list-app verbs)
    new = ${keyOf "add"}
    delete = ${keyOf "delete"}
    view = ${keyOf "open"}
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
