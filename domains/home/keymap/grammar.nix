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
#     the bare CRUD aliases (a/e/d/Enter) are shared only by the list apps
#     (todui + khalt); nvim keeps vim motions; aerc/yazi keep native bare keys.
#   * Same intent, different native command per app. A binding carries `cmd.<app>`
#     and an app participates in a binding IFF its command is present — so the
#     generators can NEVER emit a wrong/guessed command (omission, not invention).
#
# DATA MODEL
#   leader / metaLeader : the two prefixes (Nix-swappable in one edit).
#   groups              : letter -> mnemonic name (the contract; meaning is fixed).
#   shared              : Space-layer bindings present in >1 app.
#   apps.<app>          : app-specific grouped Space rows with cmd.<app>.
#   aerc                : mail action metadata; native realization in mail/aerc.
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
    f = "find";   # look for something: find files, grep, filter
    c = "compose";  # create / new / reply
    l = "language"; # LSP / language tools
    s = "sort";     # sort the current list
    b = "buffer";   # switch open things: buffers / tabs / lists
    t = "toggle";   # flip a setting: hidden, wrap, numbers, threads
    y = "yank";     # copy: path / name / text
    d = "delete";   # remove
    w = "window";   # splits / view modes / layout
    p = "project";  # project-scoped actions
    o = "open";     # open / create external
    m = "mark";     # mark, classify and assign metadata
    q = "quit";     # quit / sync / reload
    v = "version";  # git hunks, blame and diff
    a = "agent";    # anything involving an AI agent (ask, send, nvim Claude)
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

    # --- f : find -------------------------------------------------
    { keys = "f f"; desc = "Find file"; cmd = {
        nvim = "<cmd>Telescope find_files<cr>";
        yazi = "search --via=fd --args=\"--type f\"";
      }; }
    { keys = "f g"; desc = "Grep / search content"; cmd = {
        nvim = "<cmd>Telescope live_grep<cr>";
        yazi = "search --via=rg";
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

    # --- a : agent --------------------------------------------------------
    { keys = "a a"; desc = "Ask agent about item"; cmd = {
        workbench = "ask-agent";
      }; }
    { keys = "a s"; desc = "Send item to agent"; cmd.workbench = "send-agent"; }
  ];

  # App-specific grouped Space rows. Runtime paths are bound by the adapter.
  apps.nvim = [
    { keys = "g o"; desc = "Go: documents"; cmd.nvim = "<cmd>cd ~/Documents<cr>"; nvim.mode = [ "n" ]; }
    { keys = "g r"; desc = "Go: root"; cmd.nvim = "<cmd>cd /<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f b"; desc = "Find: buffers"; cmd.nvim = "<cmd>FzfLua buffers<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f h"; desc = "Find: help"; cmd.nvim = "<cmd>Telescope help_tags<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f c"; desc = "Find: commands"; cmd.nvim = "<cmd>Telescope commands<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f k"; desc = "Find: keymaps"; cmd.nvim = "<cmd>Telescope keymaps<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f n"; desc = "Find: nixos files"; cmd.nvim = "function() require(\"fzf-lua\").files({ cwd = \"~/.nixos\" }) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "f s"; desc = "Find: neovim config"; cmd.nvim = "function() require(\"fzf-lua\").files({ cwd = vim.fn.stdpath(\"config\") }) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "p s"; desc = "Session: save"; cmd.nvim = "<cmd>mksession! Session.vim<cr>"; nvim.mode = [ "n" ]; }
    { keys = "p l"; desc = "Session: load"; cmd.nvim = "<cmd>source Session.vim<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f R"; desc = "Search: resume"; cmd.nvim = "<cmd>Telescope resume<cr>"; nvim.mode = [ "n" ]; }
    { keys = "t w"; desc = "Toggle: wrap"; cmd.nvim = "<cmd>lua vim.wo.wrap = not vim.wo.wrap<cr>"; nvim.mode = [ "n" ]; }
    { keys = "t h"; desc = "Toggle: highlight search"; cmd.nvim = "<cmd>set hlsearch!<cr>"; nvim.mode = [ "n" ]; }
    { keys = "t n"; desc = "Toggle: line numbers"; cmd.nvim = "<cmd>set number!<cr>"; nvim.mode = [ "n" ]; }
    { keys = "t r"; desc = "Toggle: relative numbers"; cmd.nvim = "<cmd>set relativenumber!<cr>"; nvim.mode = [ "n" ]; }
    { keys = "t s"; desc = "Toggle: spell check"; cmd.nvim = "<cmd>set spell!<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b t"; desc = "Tab: new"; cmd.nvim = "<cmd>tabnew<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b x"; desc = "Tab: close"; cmd.nvim = "<cmd>tabclose<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b 1"; desc = "Tab: 1"; cmd.nvim = "1gt"; nvim.mode = [ "n" ]; }
    { keys = "b 2"; desc = "Tab: 2"; cmd.nvim = "2gt"; nvim.mode = [ "n" ]; }
    { keys = "b 3"; desc = "Tab: 3"; cmd.nvim = "3gt"; nvim.mode = [ "n" ]; }
    { keys = "b 4"; desc = "Tab: 4"; cmd.nvim = "4gt"; nvim.mode = [ "n" ]; }
    { keys = "y c"; desc = "Yank: to system clipboard"; cmd.nvim = "\"+y"; nvim.mode = [ "n" "x" ]; }
    { keys = "y y"; desc = "Yank: line to clipboard"; cmd.nvim = "\"+yy"; nvim.mode = [ "n" ]; }
    { keys = "d x"; desc = "Cut: to system clipboard"; cmd.nvim = "\"+d"; nvim.mode = [ "n" "x" ]; }
    { keys = "y P"; desc = "Paste: from system clipboard"; cmd.nvim = "\"+p"; nvim.mode = [ "n" "x" ]; }
    { keys = "y p"; desc = "Yank: file path"; cmd.nvim = "<cmd>let @+=expand('%:p')<cr>"; nvim.mode = [ "n" ]; }
    { keys = "y n"; desc = "Yank: filename"; cmd.nvim = "<cmd>let @+=expand('%:t')<cr>"; nvim.mode = [ "n" ]; }
    { keys = "y d"; desc = "Yank: directory"; cmd.nvim = "<cmd>let @+=expand('%:h')<cr>"; nvim.mode = [ "n" ]; }
    { keys = "y a"; desc = "Yank: entire buffer to system clipboard"; cmd.nvim = ":%y+<CR>"; nvim.mode = [ "n" ]; }
    { keys = "d d"; desc = "Delete: to black hole"; cmd.nvim = "\"_d"; nvim.mode = [ "n" "v" ]; }
    { keys = "d b"; desc = "Delete: buffer"; cmd.nvim = "<cmd>bd<cr>"; nvim.mode = [ "n" ]; }
    { keys = "d w"; desc = "Delete: trailing whitespace"; cmd.nvim = "<cmd>%s/\\s\\+$//e<cr>"; nvim.mode = [ "n" ]; }
    { keys = "w v"; desc = "Window: vertical split"; cmd.nvim = "<C-w>v"; nvim.mode = [ "n" ]; }
    { keys = "w s"; desc = "Window: horizontal split"; cmd.nvim = "<C-w>s"; nvim.mode = [ "n" ]; }
    { keys = "w q"; desc = "Window: close"; cmd.nvim = "<C-w>q"; nvim.mode = [ "n" ]; }
    { keys = "w o"; desc = "Window: close others"; cmd.nvim = "<C-w>o"; nvim.mode = [ "n" ]; }
    { keys = "w ="; desc = "Window: equal size"; cmd.nvim = "<C-w>="; nvim.mode = [ "n" ]; }
    { keys = "w +"; desc = "Window: increase height"; cmd.nvim = "<C-w>+"; nvim.mode = [ "n" ]; }
    { keys = "w -"; desc = "Window: decrease height"; cmd.nvim = "<C-w>-"; nvim.mode = [ "n" ]; }
    { keys = "w >"; desc = "Window: increase width"; cmd.nvim = "<C-w>>"; nvim.mode = [ "n" ]; }
    { keys = "w <"; desc = "Window: decrease width"; cmd.nvim = "<C-w><"; nvim.mode = [ "n" ]; }
    { keys = "b d"; desc = "Buffer: delete"; cmd.nvim = "<cmd>bd<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b a"; desc = "Buffer: delete all others"; cmd.nvim = "<cmd>%bd|e#|bd#<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b l"; desc = "Buffer: last"; cmd.nvim = "<cmd>blast<cr>"; nvim.mode = [ "n" ]; }
    { keys = "b f"; desc = "Buffer: first"; cmd.nvim = "<cmd>bfirst<cr>"; nvim.mode = [ "n" ]; }
    { keys = "o v"; desc = "Open: file explorer (Oil)"; cmd.nvim = "<cmd>Oil<cr>"; nvim.mode = [ "n" ]; }
    { keys = "o n"; desc = "Open: nixos config"; cmd.nvim = "<cmd>Oil ~/.nixos<cr>"; nvim.mode = [ "n" ]; }
    { keys = "o c"; desc = "Open: config dir"; cmd.nvim = "<cmd>Oil ~/.config<cr>"; nvim.mode = [ "n" ]; }
    { keys = "o h"; desc = "Open: home dir"; cmd.nvim = "<cmd>Oil ~<cr>"; nvim.mode = [ "n" ]; }
    { keys = "c r"; desc = "Replace: word under cursor"; cmd.nvim = ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>"; nvim.mode = [ "n" ]; }
    { keys = "t a"; desc = "Select: all"; cmd.nvim = "ggVG"; nvim.mode = [ "n" ]; }
    { keys = "l r"; desc = "Language: rename"; cmd.nvim = "function() vim.lsp.buf.rename() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l a"; desc = "Language: code action"; cmd.nvim = "function() vim.lsp.buf.code_action() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l R"; desc = "Language: references"; cmd.nvim = "function() vim.lsp.buf.references() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l s"; desc = "Language: workspace symbols"; cmd.nvim = "function() vim.lsp.buf.workspace_symbol() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l D"; desc = "Language: definition"; cmd.nvim = "function() vim.lsp.buf.definition() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l d"; desc = "Diagnostics"; cmd.nvim = "function() vim.diagnostic.open_float() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "l f"; desc = "Format"; cmd.nvim = "function() require(\"conform\").format({ async = true, lsp_format = \"fallback\" }) end"; nvim = { lua = true; mode = [ "n" "v" ]; }; }
    { keys = "l x"; desc = "Trouble: diagnostics toggle"; cmd.nvim = "<cmd>Trouble diagnostics toggle<cr>"; nvim.mode = [ "n" ]; }
    { keys = "l X"; desc = "Trouble: diagnostics toggle filter.buf=0"; cmd.nvim = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>"; nvim.mode = [ "n" ]; }
    { keys = "l S"; desc = "Trouble: symbols toggle focus=false"; cmd.nvim = "<cmd>Trouble symbols toggle focus=false<cr>"; nvim.mode = [ "n" ]; }
    { keys = "l L"; desc = "Trouble: lsp toggle focus=false win.position=right"; cmd.nvim = "<cmd>Trouble lsp toggle focus=false win.position=right<cr>"; nvim.mode = [ "n" ]; }
    { keys = "l l"; desc = "Trouble: loclist toggle"; cmd.nvim = "<cmd>Trouble loclist toggle<cr>"; nvim.mode = [ "n" ]; }
    { keys = "l q"; desc = "Trouble: qflist toggle"; cmd.nvim = "<cmd>Trouble qflist toggle<cr>"; nvim.mode = [ "n" ]; }
    { keys = "f t"; desc = "Find TODOs"; cmd.nvim = "<cmd>TodoTelescope<cr>"; nvim.mode = [ "n" ]; }
    { keys = "o t"; desc = "Tuxedo"; cmd.nvim = "<cmd>Tuxedo<cr>"; nvim.mode = [ "n" ]; }
    { keys = "m h"; desc = "Mark: harpoon add"; cmd.nvim = "function() require(\"harpoon\"):list():append() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "g 1"; desc = "Harpoon file 1"; cmd.nvim = "function() require(\"harpoon\"):list():select(1) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "g 2"; desc = "Harpoon file 2"; cmd.nvim = "function() require(\"harpoon\"):list():select(2) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "g 3"; desc = "Harpoon file 3"; cmd.nvim = "function() require(\"harpoon\"):list():select(3) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "g 4"; desc = "Harpoon file 4"; cmd.nvim = "function() require(\"harpoon\"):list():select(4) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "t m"; desc = "Toggle harpoon menu"; cmd.nvim = "function() local h = require(\"harpoon\"); h.ui:toggle_quick_menu(h:list()) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v p"; desc = "Git: preview hunk"; cmd.nvim = "function() require(\"gitsigns\").preview_hunk() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v s"; desc = "Git: stage hunk"; cmd.nvim = "function() require(\"gitsigns\").stage_hunk() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v r"; desc = "Git: reset hunk"; cmd.nvim = "function() require(\"gitsigns\").reset_hunk() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v u"; desc = "Git: undo stage hunk"; cmd.nvim = "function() require(\"gitsigns\").undo_stage_hunk() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v b"; desc = "Git: blame line"; cmd.nvim = "function() require(\"gitsigns\").blame_line() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v d"; desc = "Git: diff"; cmd.nvim = "function() require(\"gitsigns\").diffthis() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v t"; desc = "Git: toggle line blame"; cmd.nvim = "function() require(\"gitsigns\").toggle_current_line_blame() end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "v B"; desc = "Git: full blame"; cmd.nvim = "function() require(\"gitsigns\").blame_line({ full = true }) end"; nvim = { lua = true; mode = [ "n" ]; }; }
    { keys = "a a"; desc = "Agent: ClaudeCode"; cmd.nvim = "<cmd>ClaudeCode<cr>"; nvim.mode = [ "n" ]; }
    { keys = "a f"; desc = "Agent: ClaudeCodeFocus"; cmd.nvim = "<cmd>ClaudeCodeFocus<cr>"; nvim.mode = [ "n" ]; }
    { keys = "a r"; desc = "Agent: ClaudeCode --resume"; cmd.nvim = "<cmd>ClaudeCode --resume<cr>"; nvim.mode = [ "n" ]; }
    { keys = "a b"; desc = "Agent: ClaudeCodeAdd %"; cmd.nvim = "<cmd>ClaudeCodeAdd %<cr>"; nvim.mode = [ "n" ]; }
    { keys = "a s"; desc = "Agent: ClaudeCodeSend"; cmd.nvim = "<cmd>ClaudeCodeSend<cr>"; nvim.mode = [ "v" ]; }
    { keys = "a A"; desc = "Agent: ClaudeCodeDiffAccept"; cmd.nvim = "<cmd>ClaudeCodeDiffAccept<cr>"; nvim.mode = [ "n" ]; }
    { keys = "a d"; desc = "Agent: ClaudeCodeDiffDeny"; cmd.nvim = "<cmd>ClaudeCodeDiffDeny<cr>"; nvim.mode = [ "n" ]; }
  ];

  apps.yazi = [
      { keys = "g t"; desc = "Go: tmp"; cmd.yazi = "cd /tmp"; }
      { keys = "g 0"; desc = "Go: inbox"; cmd.yazi = "cd ~/000_inbox"; }
      { keys = "g 1"; desc = "Go: work"; cmd.yazi = "cd ~/100_hwc"; }
      { keys = "g 2"; desc = "Go: personal"; cmd.yazi = "cd ~/200_personal"; }
      { keys = "g 3"; desc = "Go: tech"; cmd.yazi = "cd ~/300_tech"; }
      { keys = "g 5"; desc = "Go: media"; cmd.yazi = "cd ~/500_media"; }
      { keys = "g 9"; desc = "Go: vaults"; cmd.yazi = "cd ~/900_vaults"; }
      { keys = "g p"; desc = "Go: pictures"; cmd.yazi = "cd ~/500_media/pictures"; }
      { keys = "g M"; desc = "Go: music"; cmd.yazi = "cd ~/500_media/music"; }
      { keys = "g v"; desc = "Go: videos"; cmd.yazi = "cd ~/500_media/videos"; }
      { keys = "g T"; desc = "Go: trash"; cmd.yazi = "cd ~/.local/share/Trash/files"; }
      { keys = "g m"; desc = "Go: media mount"; cmd.yazi = "cd @mediaRoot@"; }
      { keys = "g f"; desc = "Go: favorites"; cmd.yazi = "plugin bookmarks focus"; }
      { keys = "f l"; desc = "Filter"; cmd.yazi = "filter --smart"; }
      { keys = "g z"; desc = "Zoxide jump"; cmd.yazi = "plugin zoxide"; }
      { keys = "m f"; desc = "Favorite: add current folder"; cmd.yazi = "plugin bookmarks add"; }
      { keys = "m p"; desc = "Change permissions"; cmd.yazi = "plugin bookmarks 'route plugin chmod'"; }
      { keys = "t a"; desc = "Select all"; cmd.yazi = "plugin bookmarks 'route toggle_all --state=on'"; }
      { keys = "g g"; desc = "Go to top"; cmd.yazi = "plugin bookmarks 'route arrow top'"; }
      { keys = "g G"; desc = "Go to bottom"; cmd.yazi = "plugin bookmarks 'route arrow bot'"; }
      { keys = "g k"; desc = "Move up"; cmd.yazi = "plugin bookmarks 'route arrow -1'"; }
      { keys = "g j"; desc = "Move down"; cmd.yazi = "plugin bookmarks 'route arrow 1'"; }
      { keys = "g b"; desc = "Go back/parent"; cmd.yazi = "plugin bookmarks 'route leave'"; }
      { keys = "g e"; desc = "Enter/Open"; cmd.yazi = "plugin bookmarks 'route enter'"; }
      { keys = "g u"; desc = "Half page up"; cmd.yazi = "plugin bookmarks 'route arrow -50%'"; }
      { keys = "g D"; desc = "Half page down"; cmd.yazi = "plugin bookmarks 'route arrow 50%'"; }
      { keys = "g U"; desc = "Page up"; cmd.yazi = "plugin bookmarks 'route arrow -100%'"; }
      { keys = "g F"; desc = "Page down"; cmd.yazi = "plugin bookmarks 'route arrow 100%'"; }
      { keys = "o o"; desc = "Open"; cmd.yazi = "plugin bookmarks 'route open'"; }
      { keys = "o O"; desc = "Open with"; cmd.yazi = "plugin bookmarks 'route open --interactive'"; }
      { keys = "q q"; desc = "Quit"; cmd.yazi = "plugin bookmarks 'route quit'"; }
      { keys = "q c"; desc = "Cancel/Clear"; cmd.yazi = "plugin bookmarks 'route escape'"; }
      { keys = "t s"; desc = "Toggle select"; cmd.yazi = "plugin bookmarks 'route toggle'"; }
      { keys = "t A"; desc = "Toggle all"; cmd.yazi = "plugin bookmarks 'route toggle_all'"; }
      { keys = "t j"; desc = "Select & down"; cmd.yazi = "plugin bookmarks 'route select-down'"; }
      { keys = "t k"; desc = "Up & select"; cmd.yazi = "plugin bookmarks 'route select-up'"; }
      { keys = "t c"; desc = "Clear selection"; cmd.yazi = "plugin bookmarks 'route escape --select'"; }
      { keys = "y y"; desc = "Yank (copy)"; cmd.yazi = "plugin bookmarks 'route yank'"; }
      { keys = "y x"; desc = "Cut"; cmd.yazi = "plugin bookmarks 'route yank --cut'"; }
      { keys = "d d"; desc = "Delete (to trash) / remove favorite"; cmd.yazi = "plugin bookmarks 'route remove'"; }
      { keys = "d D"; desc = "Delete permanently"; cmd.yazi = "plugin bookmarks 'route remove --permanently'"; }
      { keys = "y v"; desc = "Paste here"; cmd.yazi = "plugin bookmarks 'route paste'"; }
      { keys = "y V"; desc = "Paste into hovered dir"; cmd.yazi = "plugin bookmarks 'route paste-into'"; }
      { keys = "c f"; desc = "Create file/dir"; cmd.yazi = "plugin bookmarks 'route create'"; }
      { keys = "c d"; desc = "Create directory"; cmd.yazi = "plugin bookmarks 'route create --dir'"; }
      { keys = "c r"; desc = "Rename"; cmd.yazi = "plugin bookmarks 'route rename --cursor=before_ext'"; }
      { keys = "c R"; desc = "Rename (full)"; cmd.yazi = "plugin bookmarks 'route rename'"; }
      { keys = "c l"; desc = "Symlink"; cmd.yazi = "plugin bookmarks 'route link'"; }
      { keys = "c L"; desc = "Relative symlink"; cmd.yazi = "plugin bookmarks 'route link --relative'"; }
      { keys = "c h"; desc = "Hardlink"; cmd.yazi = "plugin bookmarks 'route hardlink'"; }
      { keys = "g Z"; desc = "FZF jump"; cmd.yazi = "plugin fzf"; }
      { keys = "g l"; desc = "Focus files"; cmd.yazi = "plugin bookmarks close"; }
      { keys = "g N"; desc = "Next favorite"; cmd.yazi = "plugin bookmarks next"; }
      { keys = "g P"; desc = "Previous favorite"; cmd.yazi = "plugin bookmarks previous"; }
      { keys = "t h"; desc = "Toggle hidden"; cmd.yazi = "hidden toggle"; }
      { keys = "w i"; desc = "Inspect"; cmd.yazi = "inspect"; }
      { keys = "w h"; desc = "Help"; cmd.yazi = "help"; }
      { keys = "o s"; desc = "Shell command"; cmd.yazi = "plugin bookmarks 'route shell --block --confirm'"; }
      { keys = "o S"; desc = "Shell command"; cmd.yazi = "plugin bookmarks 'route shell --interactive'"; }
      { keys = "w j"; desc = "Preview: down"; cmd.yazi = "seek 5"; }
      { keys = "w k"; desc = "Preview: up"; cmd.yazi = "seek -5"; }
      { keys = "b j"; desc = "Next tab"; cmd.yazi = "tab_switch 1 --relative"; }
      { keys = "b k"; desc = "Prev tab"; cmd.yazi = "tab_switch -1 --relative"; }
      { keys = "s n"; desc = "Sort: natural"; cmd.yazi = "sort natural"; }
      { keys = "s a"; desc = "Sort: alphabetical"; cmd.yazi = "sort alphabetical"; }
      { keys = "s s"; desc = "Sort: size"; cmd.yazi = "sort size"; }
      { keys = "s m"; desc = "Sort: modified"; cmd.yazi = "sort mtime"; }
      { keys = "s c"; desc = "Sort: created"; cmd.yazi = "sort btime"; }
      { keys = "s e"; desc = "Sort: extension"; cmd.yazi = "sort extension"; }
      { keys = "s r"; desc = "Sort: reverse"; cmd.yazi = "sort --reverse"; }
      { keys = "b n"; desc = "Tab: new"; cmd.yazi = "tab_create --current"; }
      { keys = "b c"; desc = "Tab: close"; cmd.yazi = "tab_close"; }
      { keys = "b o"; desc = "Tab: close others"; cmd.yazi = "tab_close --all"; }
      { keys = "b 1"; desc = "Tab: 1"; cmd.yazi = "tab_switch 0"; }
      { keys = "b 2"; desc = "Tab: 2"; cmd.yazi = "tab_switch 1"; }
      { keys = "b 3"; desc = "Tab: 3"; cmd.yazi = "tab_switch 2"; }
      { keys = "b 4"; desc = "Tab: 4"; cmd.yazi = "tab_switch 3"; }
      { keys = "w s"; desc = "View: sizes"; cmd.yazi = "linemode size"; }
      { keys = "w p"; desc = "View: permissions"; cmd.yazi = "linemode permissions"; }
      { keys = "w m"; desc = "View: modified time"; cmd.yazi = "linemode mtime"; }
      { keys = "w c"; desc = "View: created time"; cmd.yazi = "linemode btime"; }
      { keys = "w n"; desc = "View: clean"; cmd.yazi = "linemode none"; }
      { keys = "y p"; desc = "Copy: full path"; cmd.yazi = "copy path"; }
      { keys = "y n"; desc = "Copy: filename"; cmd.yazi = "copy filename"; }
      { keys = "y d"; desc = "Copy: directory"; cmd.yazi = "copy dirname"; }
  ];

  # Grouped rows retain each app's action metadata and bare aliases.
  apps.todui = [
      { keys = "m p"; desc = "Priority"; }
      { keys = "m u"; desc = "Due date"; }
      { keys = "m l"; desc = "Assign list"; }
      { keys = "m j"; desc = "Assign project"; }
      { keys = "m k"; desc = "Assign context"; }

      { keys = "c c"; desc = "Add"; cmd.todui = "add"; bare = [ "a" ]; }
      { keys = "o e"; desc = "Edit"; cmd.todui = "edit"; bare = [ "e" ]; }
      { keys = "d d"; desc = "Delete"; cmd.todui = "delete"; bare = [ "d" ]; }
      { keys = "o o"; desc = "Open / view"; cmd.todui = "open"; bare = [ "enter" ]; }
  ];
  apps.khalt = [
      { keys = "c d"; desc = "Duplicate event"; }
      { keys = "o x"; desc = "Export event"; }
      { keys = "w v"; desc = "View cycle (agenda/month/quarter)"; }

      { keys = "c c"; desc = "Add"; cmd.khalt = "add"; bare = [ "a" ]; }
      { keys = "o e"; desc = "Edit"; cmd.khalt = "edit"; bare = [ "e" ]; }
      { keys = "d d"; desc = "Delete"; cmd.khalt = "delete"; bare = [ "d" ]; }
      { keys = "o o"; desc = "Open / view"; cmd.khalt = "open"; bare = [ "enter" ]; }
  ];
  # Aerc actions and descriptions have one producer. The mail adapter supplies
  # native commands and dynamic State/Domain/fact options from their contracts.
  aerc = let
    row = keys: action: desc: scope: extras: { inherit keys action desc scope; } // extras;
  in {
    stateKeys = { "do" = "a"; "dont-know" = "k"; did = "d"; look = "l"; junk = "j"; };
    domainKeys = { hwc = "h"; datax = "d"; family = "f"; personal = "p"; other = "o"; };
    bindings = [
      (row "g i" "go-do" "DO" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g k" "go-dont-know" "DONT KNOW" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g b" "go-bulk" "Bulk" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g d" "go-did" "DID" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g l" "go-look" "LOOK" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g j" "go-junk" "JUNK" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g B" "go-backlog" "Backlog" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g I" "go-inbox" "Raw inbox" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g A" "go-all" "All mail" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g u" "go-unread" "Unread" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g a" "go-archive" "Archive" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g s" "go-sent" "Sent" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g T" "go-trash" "Trash" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g z" "go-spam" "Spam" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "g _" "go-hide" "Hide-my-email" "account" { wb = { omit = "aerc folder navigation; Workbench Mail uses stages"; }; })
      (row "f f" "filter" "Filter folder by words…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f a" "all-search" "Search all mail by words…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f s" "search" "Jump to matching words…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f t" "tag-filter" "Filter folder by tag…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f T" "tag-search" "Search all mail by tag…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f d" "domain-filter" "Filter by Domain…" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "f c" "clear" "Clear filter/search" "account" { wb = { omit = "aerc list filtering and search"; }; })
      (row "s d" "sort-date" "Newest first" "account" { wb = { omit = "aerc list sorting"; }; })
      (row "s f" "sort-from" "Sender, then newest" "account" { wb = { omit = "aerc list sorting"; }; })
      (row "s s" "sort-subject" "Subject, then newest" "account" { wb = { omit = "aerc list sorting"; }; })
      (row "s a" "sort-alpha" "Alphabetical subject A–Z" "account" { wb = { omit = "aerc list sorting"; }; })
      (row "b n" "tab-next" "Next tab" "global" { wb = { omit = "Tabs belong to aerc"; }; })
      (row "b p" "tab-prev" "Previous tab" "global" { wb = { omit = "Tabs belong to aerc"; }; })
      (row "b c" "tab-close" "Close tab" "closable" { wb = { omit = "Tabs belong to aerc"; }; })
      (row "t h" "headers" "Toggle headers" "view" { wb = { omit = "Raw headers belong to aerc viewer"; }; })
      (row "t t" "fold" "Toggle selected fold" "account" { wb = { omit = "aerc thread folding"; }; })
      (row "t a" "fold-all" "Fold all threads" "account" { wb = { omit = "aerc thread folding"; }; })
      (row "w i" "images" "Local image preview (remote images blocked)" "view" { wb = { omit = "MIME image preview belongs to aerc viewer"; }; })
      (row "w n" "part-next" "Next MIME part / attachment" "view" { wb = { omit = "MIME parts belong to aerc viewer"; }; })
      (row "w p" "part-prev" "Previous MIME part / attachment" "view" { wb = { omit = "MIME parts belong to aerc viewer"; }; })
      (row "w s" "styleset" "Switch styleset…" "global" { wb = { omit = "Stylesets belong to aerc"; }; })
      (row "o t" "task" "Task handoff" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { view = [ "t" ]; }; })
      (row "o c" "calendar" "Import calendar event (no RSVP)" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; })
      (row "o p" "paperless" "Paperless handoff" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { view = [ "p" ]; }; })
      (row "o l" "links" "URL picker" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { view = [ "u" ]; }; })
      (row "c c" "compose" "Compose" "account" { wb = { handoff = "compose"; }; handoffArgs = [ "-I" ":compose" ]; bare = { list = [ "c" ]; }; })
      (row "c r" "reply" "Reply" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { view = [ "r" ]; }; })
      (row "c a" "reply-all" "Reply all" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { list = [ "C" ]; view = [ "R" ]; }; })
      (row "c f" "forward" "Forward" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { view = [ "f" ]; }; })
      (row "m j" "mark-next" "Mark and move down" "message" { wb = { omit = "aerc list selection and movement"; }; bare.list = [ "J" ]; })
      (row "m k" "mark-prev" "Mark and move up" "message" { wb = { omit = "aerc list selection and movement"; }; bare.list = [ "K" ]; })
      (row "m a" "archive" "Archive (record outcome)" "message" { wb = { verb = "archive"; }; bare = { list = [ "a" ]; view = [ "a" ]; }; })
      (row "m s" "state" "Set State…" "message" { wb = { menu = "state"; }; })
      (row "m d" "domain" "Set Domain…" "message" { wb = { menu = "domain"; }; })
      (row "m t" "tags" "Optional tags…" "message" { wb = { omit = "aerc fact/tag menus; Workbench item intents cannot supply a fact parameter or open a tag picker"; }; })
      (row "m l" "rules" "Routing rules…" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; })
      (row "m u" "unsubscribe" "Review unsubscribe" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; })
      (row "m v" "read-status" "Read/unread…" "message" { wb = { menu = "read-status"; }; bare.list = [ { key = "r"; action = "read"; verb = "mark-read"; } { key = "u"; action = "unread"; verb = "mark-unread"; } ]; })
      (row "m x" "move" "Move to folder… (no learning)" "message" { wb = { omit = "aerc folder move; Workbench moves by state with m s"; }; bare = { list = [ "X" ]; }; })
      (row "y l" "links" "Copy URL via picker" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; })
      (row "y m" "copy" "Copy to folder…" "message" { wb = { omit = "No aerc thread-load completion or message-selection contract; action could target another message"; }; bare = { list = [ "Y" ]; }; })
      (row "d d" "trash" "Trash (record outcome)" "message" { wb = { verb = "trash"; }; bare = { list = [ "d" "D" ]; view = [ "d" ]; }; })
      (row "q s" "sync" "Sync mail" "global" { wb = { omit = "aerc app control"; }; })
      (row "q r" "reload" "Reload configuration" "global" { wb = { omit = "aerc app control"; }; })
      (row "q q" "quit" "Confirm quit" "global" { wb = { omit = "aerc app control"; }; })
      (row "?" "help" "Binding sheet" "global" { wb = { omit = "aerc app control"; }; })
    ];
    menus = {
      rules = [
        { key = "a"; action = "rule-create"; desc = "Create from selected mail"; }
        { key = "m"; action = "rule-manage"; desc = "Review / disable rules"; }
      ];
      tags = [
        { key = "a"; action = "add-fact"; desc = "Add optional fact…"; }
        { key = "l"; action = "labels"; desc = "Add/remove labels…"; }
        { key = "x"; action = "clear-facts"; desc = "Clear optional facts (preserve stars/history)"; }
        { key = "n"; action = "new-tag"; desc = "Define a new optional tag"; }
      ];
      read-status = [
        { key = "r"; action = "read"; desc = "Read"; }
        { key = "u"; action = "unread"; desc = "Unread"; }
      ];
    };
  };

  #--------------------------------------------------------------------------
  # Bare CRUD verbs shared by the LIST apps (todui + khalt). Kept bare for
  # speed; also aliased under Space (the generators emit a `Space <verb>` alias
  # so which-key/forgetfulness has a safety net — see spec 3.1c).
  #--------------------------------------------------------------------------

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
  # logical tool to focus (mapped to the layout's tab index in to-zellij.nix).
  # HUB digits are NOT listed here: the Workbench hub registry produces them
  # (zellij/parts/tabs.nix hubJumps) and to-zellij.nix appends them, asserting
  # grammar.meta contains no digits. Tool (t/c/m/f/e/a) and nav/utility letters
  # (j/k/n/p/]/[/w/z/s/d/Q) below.
  #--------------------------------------------------------------------------
  meta = [
    # Tool tabs.
    { key = "t"; intent = "tasks";    desc = "Tasks (todui)";  target = "tool:todui"; }
    { key = "c"; intent = "calendar"; desc = "Calendar (khalt)"; target = "tool:khalt"; }
    { key = "m"; intent = "mail";     desc = "Mail (aerc)";    target = "tool:aerc"; }
    { key = "f"; intent = "files";    desc = "Files (yazi)";   target = "tool:yazi"; }
    { key = "e"; intent = "edit";     desc = "Edit (nvim)";    target = "tool:nvim"; }
    { key = "a"; intent = "agents";   desc = "Agents (herdr)"; target = "tool:herdr"; }
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
