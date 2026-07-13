# domains/home/keymap

The **single source of truth** for the unified workbench keymap. Edit
`grammar.nix` and every TUI re-keys on the next `hms` — the keybinding analogue
of `domains/home/theme/` (palette → every app's colours).

Plain-language design + rationale: `docs/UNIFIED-KEYMAP-SPEC.md`.

## Structure

```
index.nix              Options hwc.home.keymap.{enable,leader,metaLeader,grammar};
                       materializes grammar.nix as the read-only token set.
grammar.nix            THE file you edit. Groups, shared Space bindings, per-app
                       major modes, list-app bare verbs, two-column nav, meta map.
parts/
  to-zellij.nix        meta -> zellij keybinds KDL (inter-app Alt+Space layer)
  to-yazi.nix          grammar -> keymap.toml [mgr] fragment
  to-nvim.nix          grammar -> lua (Space layer + which-key groups)
  to-aerc.nix          grammar -> binds.conf fragment (composes with tags.nix)
  to-khalt.nix         grammar -> [keybindings] block + KHALT_LEADER_TREE json
  to-todui.nix         grammar -> TODUI_KEYMAP json (env)
  to-workbench.nix     grammar -> WORKBENCH_KEYMAP json (env)
```

## The two layers

- **`Space`** (intra-app): act inside the focused app. Same grammar everywhere.
  Groups: `g`go `f`search `s`sort `b`buffer `t`toggle `y`yank `d`delete `w`window
  `p`project `o`open `m`major(app's-own) `q`quit.
- **`Alt+Space`** (inter-app): jump between panes. Lives ONLY in zellij. Audited
  clear of Hyprland (all SUPER; only Super+Space=wofi) and every TUI (only
  nvim-cmp uses Ctrl+Space). One Nix variable — swap in `grammar.nix`.

## Activation status

The module + its safe, high-value wirings are **already applied and git-staged**
on `feat/workbench-zellij` (one `hms` away — run it on the LAPTOP; desktop
profile, needs a real zellij session for QA). Every wiring is **guarded** by
`km ? <field>`, so each is a no-op if the grammar is somehow absent.

WIRED (staged):
1. **Module imported** — `profiles/desktop/home.nix`:
   `../../domains/home/keymap/index.nix` (note: the file, not the dir — Nix
   imports `default.nix` from a dir, and this module is `index.nix`).
2. **zellij meta layer** (`apps/zellij/index.nix`) — `${metaKeybinds}` from
   `to-zellij` injected into `config.kdl`. THE centerpiece: `Alt+Space` → jump
   map; `clear-defaults=true` stops zellij eating aerc/yazi's Ctrl keys.
3. **khalt** (`apps/khalt/index.nix`) — `to-khalt`'s `keybindingsBlock` appended
   to `configText` (gives khalt the shared list verbs a/e/d/Enter).
4. **todui & workbench** — `to-todui`/`to-workbench` JSON staged as
   `~/.config/{todui,workbench}/keymap.json` (the app-side readers consume these
   once built; writing them now is harmless and the data is ready).

DEFERRED (intentionally NOT auto-edited — they already implement the grammar by
hand, so converting them to generator-sourced is a no-behavior-change refactor
that needs runtime QA, not a blind stage-and-hms):
   - **yazi** — append `to-yazi`'s `keymapFragment` inside the existing
     `[mgr] prepend_keymap` array (replacing the hand-written g/f/s/b block).
   - **nvim** — source `to-nvim`'s `lua` after `mapleader`; add the `which-key`
     plugin (today absent) so the popup renders (incl. baked-in keymaps).
   - **aerc** — splice `to-aerc`'s `bindsFragment` under `[messages]` (composes
     with the tag-generated `<Space>g`/`<Space>m`; once aerc cmds are seeded in
     grammar.nix). aerc already matches the grammar by hand today.

## App-side prerequisites (separate repos under ~/600_apps, staged not done)

These three apps need code before they are *driven* by the grammar (until then
they keep current keys; exporting the env is harmless but the app MUST log when
the var is present-but-unread, so drift can't hide — spec premortem #6):

- **todui** — read `TODUI_KEYMAP` via its env→toml→default precedence
  (`src/todui/config.py`); render `BINDINGS` + leader menu from it instead of
  hard-coded Python. *Largest change.*
- **workbench** — read `WORKBENCH_KEYMAP` → `Keymap.from_actions(globals_=…)`;
  and DROP the `Space t/c/m` app-jumps (they become `Alt+Space`, owned by zellij).
- **khalt** — teach `khalt_leader.build_keymap()` to read `KHALT_LEADER_TREE`
  (the json from `to-khalt`) so the menu GROUPS come from data, not Python. Until
  then khalt drives only leaf keys (a/e/d via `[keybindings]`) — a documented
  subset.

## Verify before trusting (real-world checks, not eval)

- `Ctrl+b` enters the meta (tmux) mode reliably in kitty→zellij. (We tried
  `Alt+Space` first; kitty did NOT deliver it to zellij — it leaked through to
  the focused pane, whose Space-leader then mis-fired. Ctrl-chords are encoded
  reliably; that's why the meta leader is a Ctrl-chord, like tmux/screen.)
- `zellij setup --check` reports "Config file: Well defined" — the meta block,
  GoToTab jumps, and scroll mode all parse (a runtime check `nix build` can't do).
- kitty keyboard protocol on, so `Ctrl+j` ≠ Enter (two-column nav, spec §3.1b).
- todui/khalt/workbench log a missing/unread `*_KEYMAP` rather than failing silent.

## Changelog

- 2026-07-13 — **CRM hub jump.** Added meta key `r` (`Ctrl+Space r`) → CRM hub in
  `grammar.nix`, second in hub order (between hwc and datax). The layout KDL,
  `GoToTab` indices, and `WORKBENCH_TABS` all derive from the shared `tabs.hubs`
  list, so they stay coherent (tab order now: hwc · crm · datax · server · brief ·
  tasks · cal · files · mail · edit).
- 2026-06-26 — **Ctrl = workbench layer; in-app side-nav → Alt.** zellij now
  binds `Ctrl j`/`Ctrl k` to cycle tabs directly (plus `Ctrl Space` = meta card),
  so Ctrl is the workbench/meta layer. In-app two-column nav moved off Ctrl onto
  **Alt+j/k** (passes through zellij to the focused pane): `columns.secondary`,
  aerc `<A-j>/<A-k>` (folders), todui `alt+j/k` (sidebar), yazi `<A-j>/<A-k>`
  (preview seek). Also fixed the plugin's `go_to_tab` off-by-one (0-based API vs
  1-based grammar index) and made its floating pane borderless (no double frame).
- 2026-06-26 — **Meta layer → `zellij-which` plugin card.** The meta-leader
  (`Ctrl Space`) now launches the `zellij-which` floating which-key card (custom
  Rust→wasm zellij plugin, `~/600_apps/zellij-which`, flake input) instead of the
  subtle built-in status-bar `tmux` mode. `to-zellij.nix` gains optional
  `pluginWasm`/`colors` args: when `pluginWasm` is set it emits a
  `LaunchOrFocusPlugin` bind whose `entries` are generated from the SAME
  `grammar.meta` (key|verb|arg|label) — so the card can't go stale; else it falls
  back to the old tmux-mode block. Card uses a distinct blue (`info`) accent to
  signal meta scope vs the inner copper app cards. `kill` (Quit) omitted (no
  plugin verb). First plugin load prompts for zellij permissions (grant once).
- 2026-06-18 — **Flat hub-pages + `Ctrl Space` leader.** The single multi-hub
  "home" tab is dissolved: each workbench hub is now its own zellij tab
  (`workbench --hub <id>`), peer of the tool tabs (order: hwc · datax · server ·
  brief · tasks · cal · files · mail · edit). The `meta` map gains hub jumps
  (h→hwc, x→datax, v→server, b→brief) alongside the tool jumps (t/c/m/f/e); the
  old `h→host` entry is gone. `to-zellij.nix` now derives `GoToTab` indices from
  `apps/zellij/parts/tabs.nix` (hubs ++ tools) so layout/keymap can't drift.
  metaLeader `Ctrl b`→**`Ctrl Space`** — verified via `showkey -a` to arrive as
  NUL (0x00), distinct from a bare Space (0x20), so it can't mis-fire an app's
  Space-leader (unlike `Alt Space`). Revert to a Ctrl-letter in `grammar.nix` if
  kitty's enhanced-keyboard mode ever swallows it.
- 2026-06-16 — Meta layer hardened (runtime fixes the eval missed). metaLeader
  `Alt Space`→`Ctrl b` (kitty didn't deliver Alt+Space to zellij → it leaked to
  the host's Space-leader and mis-spawned). Jumps now emit `GoToTab <index>`
  (zellij rejects `GoToTabName` in keybinds). Added scrollback (`Ctrl+b s`, with
  a `scroll` mode block) + detach (`Ctrl+b d`) — clear-defaults had stripped
  zellij's own, leaving a long-lived session unable to scroll or detach. n/p
  repurposed to tab-nav (every tool tab is single-pane). khalt keybindings made
  honest: bind add/delete/open→new/delete/view; DROP the false `e`=edit (khal has
  no safe single-key edit — it edits via `view`/Enter — so khalt omits that verb
  per the per-app omission rule; `e` stays khal's native export).
- 2026-06-15 — Module created + wired. grammar.nix (source of truth) + index.nix
  (theme-mirrored options) + 7 generators + this README. WIRED & git-staged on
  `feat/workbench-zellij`: profile import, zellij meta layer, khalt list-verbs,
  todui/workbench keymap.json staging — all guarded, one `hms` away (laptop).
  DEFERRED: yazi/nvim/aerc generator-sourcing (already conform by hand; QA-gated
  refactor). App-side readers (todui/workbench/khalt Python) staged, not built.
