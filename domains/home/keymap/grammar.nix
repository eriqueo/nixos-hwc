# domains/home/keymap/grammar.nix
#
# THE SINGLE SOURCE OF TRUTH for the unified workbench keymap.
#
# Edit THIS file and every consumer (yazi, nvim, aerc, khalt, todui, the
# workbench host, zellij) re-keys on the next `hms` — exactly as editing a
# palette in domains/home/theme/ re-themes every app. The parts/to-<app>.nix
# generators are pure functions of this data; they never invent bindings.
#
# DESIGN (see docs/UNIFIED-KEYMAP-SPEC.md for the plain-language rationale):
#   * Two layers. `leader` (Space) = act INSIDE the focused app. `metaLeader`
#     (Alt+Space) = jump BETWEEN apps; lives in zellij, never in an app.
#   * Consistency is by ROLE, not global. The Space groups below are universal;
#     the bare `listVerbs` (a/e/d/Enter) are shared only by the list apps
#     (todui + khalt); nvim keeps vim motions; aerc/yazi keep native bare keys.
#   * Same intent, different native command per app. A binding carries `cmd.<app>`
#     and an app participates in a binding IFF its command is present — so the
#     generators can NEVER emit a wrong/guessed command (omission, not invention).
#
# DATA MODEL
#   leader / metaLeader : the two prefixes (Nix-swappable in one edit).
#   groups              : letter -> mnemonic name (the contract; meaning is fixed).
#   shared              : Space-layer bindings present in >1 app.
#   major.<app>         : that app's `Space m` (major-mode) table; aerc = "tags"
#                         meaning "delegated to domains/mail/aerc/parts/tags.nix".
#   listVerbs           : bare CRUD verbs shared by todui + khalt.
#   columns             : the two-column nav convention (primary vs side column).
#   meta                : the Alt+Space jump map (key -> pane target).

{ lib }:

rec {
  #--------------------------------------------------------------------------
  # The two prefixes. Change `metaLeader` here and zellij re-binds (the only
  # place a global modifier chord is intercepted).
  #   * `leader` (Space) is the INTRA-app prefix (handled inside each app).
  #   * `metaLeader` is the INTER-app prefix, intercepted by zellij.
  # metaLeader is `Ctrl Space` — verified (2026-06-18 `showkey -a`) to arrive as
  # NUL (0x00), DISTINCT from a bare Space (0x20), so it can't mis-fire an app's
  # Space-leader the way `Alt Space` did (Alt+Space = ESC+Space leaked through
  # kitty → the spawn-in-home bug). Shift+Space was ruled out (identical to Space).
  # If kitty's enhanced-keyboard mode ever swallows it, revert this one line to a
  # Ctrl-letter (e.g. `Ctrl b`) — the binding generator (to-zellij.nix) is generic.
  #--------------------------------------------------------------------------
  leader     = " ";            # Space
  metaLeader = "Ctrl Space";   # zellij switches to `meta` (tmux) mode on this chord

  #--------------------------------------------------------------------------
  # Group letters. The MEANING is the cross-app promise. An app omits groups it
  # has no use for, but never repurposes a letter.
  #--------------------------------------------------------------------------
  groups = {
    g = "go";       # navigate: dirs, mail folders, calendar dates, top/bottom
    f = "search";   # look for something: find files, grep, filter
    s = "sort";     # sort the current list
    b = "buffer";   # switch open things: buffers / tabs / lists
    t = "toggle";   # flip a setting: hidden, wrap, numbers, threads
    y = "yank";     # copy: path / name / text
    d = "delete";   # remove
    w = "window";   # splits / view modes / layout
    p = "project";  # project-scoped actions
    o = "open";     # open / create external
    m = "major";    # THIS app's own verbs (the per-app drawer)
    q = "quit";     # quit / sync / reload
  };

  #--------------------------------------------------------------------------
  # Shared Space-layer bindings. `keys` is the chord AFTER the leader,
  # space-separated. `cmd.<app>` is the native realization; an app without a
  # command for a binding simply does not get it. Populate incrementally — the
  # machinery is complete, the data grows. Commands below are derived from the
  # live inventory (the existing per-app configs), not guessed.
  #--------------------------------------------------------------------------
  shared = [
    # --- g : go / navigate -------------------------------------------------
    { keys = "g h"; desc = "Home"; cmd = {
        yazi = "cd ~";
        nvim = "<cmd>cd ~ | echo 'cwd ~'<cr>";
      }; }
    { keys = "g c"; desc = "Config (~/.config)"; cmd = {
        yazi = "cd ~/.config";
        nvim = "<cmd>cd ~/.config<cr>";
      }; }
    { keys = "g n"; desc = "NixOS config"; cmd = {
        yazi = "cd ~/.nixos";
        nvim = "<cmd>cd ~/.nixos<cr>";
      }; }
    { keys = "g d"; desc = "Downloads"; cmd = {
        yazi = "cd ~/Downloads";
        nvim = "<cmd>cd ~/Downloads<cr>";
      }; }

    # --- f : search / find -------------------------------------------------
    { keys = "f f"; desc = "Find file"; cmd = {
        nvim = "<cmd>Telescope find_files<cr>";
        # yazi: handled by its native smart-filter (kept in keymap.nix); listed
        # here so which-key shows the group consistently.
      }; }
    { keys = "f g"; desc = "Grep / search content"; cmd = {
        nvim = "<cmd>Telescope live_grep<cr>";
      }; }
    { keys = "f r"; desc = "Recent files"; cmd = {
        nvim = "<cmd>Telescope oldfiles<cr>";
      }; }

    # --- b : buffers / tabs / lists ---------------------------------------
    { keys = "b b"; desc = "List buffers/tabs"; cmd = {
        nvim = "<cmd>Telescope buffers<cr>";
      }; }
    { keys = "b n"; desc = "Next"; cmd = {
        nvim = "<cmd>bnext<cr>";
      }; }
    { keys = "b p"; desc = "Previous"; cmd = {
        nvim = "<cmd>bprevious<cr>";
      }; }
  ];

  #--------------------------------------------------------------------------
  # Per-app major mode (Space m ...). These are the app-specific verbs that do
  # NOT generalize; quarantined here so the shared groups stay clean. aerc =
  # "tags" => its Space m table is generated from domains/mail/aerc/parts/tags.nix
  # and composed in, not duplicated here.
  #--------------------------------------------------------------------------
  major = {
    todui = [
      { keys = "p"; desc = "Priority"; }
      { keys = "u"; desc = "Due date"; }
      { keys = "l"; desc = "Assign list"; }
      { keys = "j"; desc = "Assign project"; }
      { keys = "k"; desc = "Assign context"; }
    ];
    khalt = [
      { keys = "p"; desc = "Duplicate event"; }
      { keys = "x"; desc = "Export event"; }
      { keys = "v"; desc = "View cycle (agenda/month/quarter)"; }
    ];
    yazi = [
      { keys = "c"; desc = "Change permissions"; }
      { keys = "v"; desc = "View mode"; }
    ];
    nvim = [
      { keys = "r"; desc = "LSP rename"; cmd = "<cmd>lua vim.lsp.buf.rename()<cr>"; }
      { keys = "a"; desc = "LSP code action"; cmd = "<cmd>lua vim.lsp.buf.code_action()<cr>"; }
      { keys = "f"; desc = "LSP format"; cmd = "<cmd>lua vim.lsp.buf.format()<cr>"; }
      { keys = "R"; desc = "LSP references"; cmd = "<cmd>Telescope lsp_references<cr>"; }
      { keys = "s"; desc = "Save session"; cmd = "<cmd>mksession!<cr>"; }
    ];
    aerc = "tags";
  };

  #--------------------------------------------------------------------------
  # Bare CRUD verbs shared by the LIST apps (todui + khalt). Kept bare for
  # speed; also aliased under Space (the generators emit a `Space <verb>` alias
  # so which-key/forgetfulness has a safety net — see spec 3.1c).
  #--------------------------------------------------------------------------
  listVerbs = [
    { key = "a";     intent = "add";    desc = "Add"; }
    { key = "e";     intent = "edit";   desc = "Edit"; }
    { key = "d";     intent = "delete"; desc = "Delete"; }
    { key = "enter"; intent = "open";   desc = "Open / view"; }
  ];

  #--------------------------------------------------------------------------
  # Two-column nav: same keys, modifier picks the column. Modifier doctrine:
  # **Ctrl is the workbench (meta) layer** — zellij now binds Ctrl+j/k to cycle
  # tabs and Ctrl+Space to the meta which-key. So in-app side-column nav moved
  # off Ctrl onto **Alt** to avoid the collision (Alt passes through zellij to
  # the focused app). primary = bare keys; secondary = Alt+keys.
  #--------------------------------------------------------------------------
  columns = {
    primary   = { down = "j";     up = "k"; };       # tasks / messages / files
    secondary = { down = "alt+j"; up = "alt+k"; };   # lists / folders / side col
  };

  #--------------------------------------------------------------------------
  # The meta layer (metaLeader -> zellij `meta` mode -> one key). `target` is the
  # logical hub-page/tool to focus (mapped to the layout's tab index in
  # to-zellij.nix). HUB jumps (h/x/v/b → hwc/datax/server/brief) + TOOL jumps
  # (t/c/m/f/e) are all disjoint from each other AND from the nav/utility letters
  # (n/p/]/[/w/z/s/d/Q) — no internal collision.
  #--------------------------------------------------------------------------
  meta = [
    # Hub-pages (each its own workbench --hub <id> tab).
    { key = "h"; intent = "hub-hwc";    desc = "HWC";    target = "hwc"; }
    { key = "r"; intent = "hub-crm";    desc = "CRM";    target = "crm"; }
    { key = "x"; intent = "hub-datax";  desc = "DataX";  target = "datax"; }
    { key = "v"; intent = "hub-server"; desc = "Server"; target = "server"; }
    { key = "b"; intent = "hub-brief";  desc = "Brief";  target = "brief"; }
    # Tool tabs.
    { key = "t"; intent = "tasks";    desc = "Tasks (todui)";  target = "todui"; }
    { key = "c"; intent = "calendar"; desc = "Calendar (khalt)"; target = "khalt"; }
    { key = "m"; intent = "mail";     desc = "Mail (aerc)";    target = "mail"; }
    { key = "f"; intent = "files";    desc = "Files (yazi)";   target = "files"; }
    { key = "e"; intent = "edit";     desc = "Edit (nvim)";    target = "edit"; }
    # tab navigation (n/p AND ]/[ — every tool tab is single-pane, so next/prev
    # *tab* is what you actually want; pane focus lives behind the pane-picker).
    # j/k CYCLE left/right and STAY in meta mode (press repeatedly to walk the
    # tab bar; Esc or the leader exits) — the natural "cycle through tabs" flow,
    # vs the letter jumps above which jump-and-exit. n/p and ]/[ stay as one-shot
    # next/prev for muscle memory.
    { key = "j"; intent = "cycle-prev"; desc = "◀ Tab (cycle)"; }
    { key = "k"; intent = "cycle-next"; desc = "Tab ▶ (cycle)"; }
    { key = "n"; intent = "next-tab"; desc = "Next tab"; }
    { key = "p"; intent = "prev-tab"; desc = "Prev tab"; }
    { key = "bracketright"; intent = "next-tab"; desc = "Next tab"; }
    { key = "bracketleft";  intent = "prev-tab"; desc = "Prev tab"; }
    { key = "w"; intent = "pane-picker"; desc = "Pane picker"; }
    { key = "z"; intent = "zoom";        desc = "Zoom pane"; }
    # Session lifecycle / scrollback — without these (clear-defaults strips
    # zellij's own) a long-lived ops session can't scroll output or detach.
    { key = "s"; intent = "scroll";      desc = "Scrollback"; }
    { key = "d"; intent = "detach";      desc = "Detach (keep running)"; }
    { key = "Q"; intent = "kill";        desc = "Kill session"; }
  ];
}
