# domains/home/apps/yazi/parts/keymap.nix
{ lib, grammar, mediaRoot }:
let
  spaceKeymap = import ../../../keymap/parts/to-yazi.nix {
    inherit lib grammar mediaRoot;
  };
in
{
  # Keymap configuration for Yazi - Neovim-style bindings
  "yazi/keymap.toml" = {
    text = ''
    # ~/.config/yazi/keymap.toml
    # Neovim-inspired keybindings with Space as leader

    [mgr]
    prepend_keymap = [
      # ══════════════════════════════════════════════════════════════════
      # NAVIGATION - g prefix (like neovim's g commands)
      # ══════════════════════════════════════════════════════════════════
      # Core vim motions
      { on = [ "g", "g" ], run = "plugin bookmarks 'route arrow top'", desc = "Go to top" },
      { on = [ "G" ], run = "plugin bookmarks 'route arrow bot'", desc = "Go to bottom" },

      # Quick directory jumps: g + letter (no space needed - faster)
      { on = [ "g", "h" ], run = "cd ~", desc = "Go: home" },
      { on = [ "g", "c" ], run = "cd ~/.config", desc = "Go: config" },
      { on = [ "g", "n" ], run = "cd ~/.nixos", desc = "Go: nixos" },
      { on = [ "g", "d" ], run = "cd ~/Downloads", desc = "Go: downloads" },
      { on = [ "g", "t" ], run = "cd /tmp", desc = "Go: tmp" },

      # Numbered folders (your PARA-style structure)
      { on = [ "g", "0" ], run = "cd ~/000_inbox", desc = "Go: inbox" },
      { on = [ "g", "1" ], run = "cd ~/100_hwc", desc = "Go: work" },
      { on = [ "g", "2" ], run = "cd ~/200_personal", desc = "Go: personal" },
      { on = [ "g", "3" ], run = "cd ~/300_tech", desc = "Go: tech" },
      { on = [ "g", "5" ], run = "cd ~/500_media", desc = "Go: media" },
      { on = [ "g", "9" ], run = "cd ~/900_vaults", desc = "Go: vaults" },

      # Media subfolders
      { on = [ "g", "p" ], run = "cd ~/500_media/pictures", desc = "Go: pictures" },
      { on = [ "g", "m" ], run = "cd ~/500_media/music", desc = "Go: music" },
      { on = [ "g", "v" ], run = "cd ~/500_media/videos", desc = "Go: videos" },

      # Special locations
      { on = [ "g", "T" ], run = "cd ~/.local/share/Trash/files", desc = "Go: trash" },

      # Space actions come from the shared grammar.
      ${spaceKeymap.keymapFragment}
      { on = [ "f" ], run = "filter --smart", desc = "Filter" },
      { on = [ "<Tab>" ], run = "tab_switch 1 --relative", desc = "Next tab" },
      { on = [ "<S-Tab>" ], run = "tab_switch -1 --relative", desc = "Prev tab" },

      # ══════════════════════════════════════════════════════════════════
      # CORE VIM MOTIONS
      # ══════════════════════════════════════════════════════════════════
      { on = [ "k" ], run = "plugin bookmarks 'route arrow -1'", desc = "Move up" },
      { on = [ "j" ], run = "plugin bookmarks 'route arrow 1'", desc = "Move down" },
      { on = [ "<Up>" ], run = "plugin bookmarks 'route arrow -1'", desc = "Move up" },
      { on = [ "<Down>" ], run = "plugin bookmarks 'route arrow 1'", desc = "Move down" },
      { on = [ "h" ], run = "plugin bookmarks 'route leave'", desc = "Go back/parent" },
      { on = [ "l" ], run = "plugin bookmarks 'route enter'", desc = "Enter/Open" },
      { on = [ "<Left>" ], run = "plugin bookmarks 'route leave'", desc = "Go back/parent" },
      { on = [ "<Right>" ], run = "plugin bookmarks 'route enter'", desc = "Enter/Open" },
      { on = [ "-" ], run = "plugin bookmarks 'route leave'", desc = "Parent directory" },
      { on = [ "<C-u>" ], run = "plugin bookmarks 'route arrow -50%'", desc = "Half page up" },
      { on = [ "<C-d>" ], run = "plugin bookmarks 'route arrow 50%'", desc = "Half page down" },
      { on = [ "<C-b>" ], run = "plugin bookmarks 'route arrow -100%'", desc = "Page up" },
      { on = [ "<C-f>" ], run = "plugin bookmarks 'route arrow 100%'", desc = "Page down" },
      { on = [ "<Enter>" ], run = "plugin bookmarks 'route open'", desc = "Open" },
      { on = [ "<S-Enter>" ], run = "plugin bookmarks 'route open --interactive'", desc = "Open with" },
      { on = [ "q" ], run = "plugin bookmarks 'route quit'", desc = "Quit" },
      { on = [ "<Esc>" ], run = "plugin bookmarks 'route escape'", desc = "Cancel/Clear" },

      # ══════════════════════════════════════════════════════════════════
      # SELECTION (vim visual mode style)
      # ══════════════════════════════════════════════════════════════════
      { on = [ "v" ], run = "plugin bookmarks 'route toggle'", desc = "Toggle select" },
      { on = [ "V" ], run = "plugin bookmarks 'route toggle_all'", desc = "Toggle all" },
      { on = [ "J" ], run = "plugin bookmarks 'route select-down'", desc = "Select & down" },
      { on = [ "K" ], run = "plugin bookmarks 'route select-up'", desc = "Up & select" },
      { on = [ "U" ], run = "plugin bookmarks 'route escape --select'", desc = "Clear selection" },

      # ══════════════════════════════════════════════════════════════════
      # FILE OPERATIONS (vim-inspired)
      # ══════════════════════════════════════════════════════════════════
      # Yank/Copy
      { on = [ "y" ], run = "plugin bookmarks 'route yank'", desc = "Yank (copy)" },

      # Delete
      { on = [ "d" ], run = "plugin bookmarks 'route remove'", desc = "Delete (to trash) / remove favorite" },
      { on = [ "D" ], run = "plugin bookmarks 'route remove --permanently'", desc = "Delete permanently" },

      # Cut (like vim's d but for moving)
      { on = [ "x" ], run = "plugin bookmarks 'route yank --cut'", desc = "Cut" },

      # Paste
      { on = [ "p" ], run = "plugin bookmarks 'route paste'", desc = "Paste here" },
      { on = [ "P" ], run = "plugin bookmarks 'route paste-into'", desc = "Paste into hovered dir" },

      # Create/Rename
      { on = [ "o" ], run = "plugin bookmarks 'route open'", desc = "Open" },
      { on = [ "a" ], run = "plugin bookmarks 'route create'", desc = "Create file/dir / add favorite" },
      { on = [ "O" ], run = "plugin bookmarks 'route open --interactive'", desc = "Open with" },
      { on = [ "r" ], run = "plugin bookmarks 'route rename --cursor=before_ext'", desc = "Rename" },
      { on = [ "R" ], run = "plugin bookmarks 'route rename'", desc = "Rename (full)" },

      # Links
      { on = [ "s" ], run = "plugin bookmarks 'route link'", desc = "Symlink" },
      { on = [ "S" ], run = "plugin bookmarks 'route link --relative'", desc = "Relative symlink" },
      { on = [ "_" ], run = "plugin bookmarks 'route link --relative'", desc = "Relative symlink" },
      { on = [ "<C-->" ], run = "plugin bookmarks 'route hardlink'", desc = "Hardlink" },

      # ══════════════════════════════════════════════════════════════════
      # QUICK ACCESS
      # ══════════════════════════════════════════════════════════════════
      { on = [ "z" ], run = "plugin zoxide", desc = "Zoxide jump" },
      { on = [ "Z" ], run = "plugin fzf", desc = "FZF jump" },
      { on = [ "," ], run = "plugin bookmarks focus", desc = "Favorites" },
      { on = [ "<A-h>" ], run = "plugin bookmarks focus", desc = "Focus favorites" },
      { on = [ "<A-l>" ], run = "plugin bookmarks close", desc = "Focus files" },
      { on = [ "<A-j>" ], run = "plugin bookmarks next", desc = "Next favorite" },
      { on = [ "<A-k>" ], run = "plugin bookmarks previous", desc = "Previous favorite" },
      { on = [ "." ], run = "hidden toggle", desc = "Toggle hidden" },
      { on = [ "i" ], run = "inspect", desc = "Inspect" },
      { on = [ "?" ], run = "help", desc = "Help" },
      { on = [ "!" ], run = "plugin bookmarks 'route shell --block --confirm'", desc = "Shell command" },
      { on = [ ":" ], run = "plugin bookmarks 'route shell --block --confirm'", desc = "Shell (vim-style)" },
      { on = [ ";" ], run = "plugin bookmarks 'route shell --interactive'", desc = "Shell command" },
      { on = [ "$" ], run = "plugin bookmarks 'route shell --interactive'", desc = "Open shell here" },
      { on = [ "<C-s>" ], run = "plugin bookmarks 'route shell --interactive'", desc = "Open shell here" },

      # ══════════════════════════════════════════════════════════════════
      # PREVIEW
      # ══════════════════════════════════════════════════════════════════
      { on = [ "<A-J>" ], run = "seek 5", desc = "Preview: down" },
      { on = [ "<A-K>" ], run = "seek -5", desc = "Preview: up" },
    ]

    [tasks]
    prepend_keymap = [
      { on = [ "<Esc>" ], run = "close", desc = "Close" },
      { on = [ "q" ], run = "close", desc = "Close" },
      { on = [ "k" ], run = "arrow -1", desc = "Up" },
      { on = [ "j" ], run = "arrow 1", desc = "Down" },
      { on = [ "<C-c>" ], run = "cancel", desc = "Cancel task" },
    ]

    [input]
    prepend_keymap = [
      { on = [ "<C-a>" ], run = "move bol", desc = "Start of line" },
      { on = [ "<C-e>" ], run = "move eol", desc = "End of line" },
      { on = [ "<C-f>" ], run = "move 1", desc = "Forward char" },
      { on = [ "<C-b>" ], run = "move -1", desc = "Backward char" },
      { on = [ "<C-w>" ], run = "kill backward", desc = "Delete word back" },
      { on = [ "<C-u>" ], run = [ "move bol", "kill eol" ], desc = "Clear line" },
      { on = [ "<Enter>" ], run = "close --submit", desc = "Submit" },
      { on = [ "<Esc>" ], run = "close", desc = "Cancel" },
    ]

    [select]
    prepend_keymap = [
      { on = [ "k" ], run = "arrow -1", desc = "Up" },
      { on = [ "j" ], run = "arrow 1", desc = "Down" },
      { on = [ "<C-u>" ], run = "arrow -50%", desc = "Half page up" },
      { on = [ "<C-d>" ], run = "arrow 50%", desc = "Half page down" },
      { on = [ "<Enter>" ], run = "close --submit", desc = "Select" },
      { on = [ "<Esc>" ], run = "close", desc = "Cancel" },
    ]
    '';
  };
}
