# domains/home/keymap/parts/to-todui.nix
#
# grammar -> TODUI_KEYMAP JSON (an env var the app reads, mirroring TODUI_PALETTE).
#
# todui's keys are hard-coded Python today (src/todui/tui/app.py BINDINGS). To be
# DRIVEN by this file, todui must learn to read TODUI_KEYMAP via its existing
# env→toml→default precedence (src/todui/config.py) and render its BINDINGS +
# leader menu from it. That app-side change is a prerequisite (staged). Until it
# lands, exporting this env is harmless (the app ignores an unknown var) — but
# todui MUST log when the var is present-but-unread so the drift can't hide
# silently (spec premortem #6). This generator is ready now.
#
# Pure function: returns { json = "<json>"; }.

{ lib, grammar }:

let
  json = builtins.toJSON {
    leader    = grammar.leader;
    groups    = grammar.groups;
    # bare list-app verbs (a/e/d/Enter) — todui's fast keys, also Space-aliased
    listVerbs = grammar.listVerbs;
    columns   = grammar.columns;              # j/k primary, ctrl+j/k side column
    major     = map (m: { key = m.keys; desc = m.desc; }) (grammar.major.todui or []);
  };
in
{ inherit json; }
