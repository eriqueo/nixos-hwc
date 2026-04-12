# domains/home/apps/yazi/parts/keymap.nix
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
      { on = [ "g", "g" ], run = "arrow top", desc = "Go to top" },
      { on = [ "G" ], run = "arrow bot", desc = "Go to bottom" },

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

      # ══════════════════════════════════════════════════════════════════
      # LEADER COMMANDS - Space prefix (like neovim leader)
      # ══════════════════════════════════════════════════════════════════

      # <Space>g - Alternative go commands (via plugin for extensibility)
      { on = [ "<Space>", "g", "g" ], run = "plugin bookmarks", desc = "Go: show all bookmarks" },
      { on = [ "<Space>", "g", "m" ], run = "cd /mnt/media", desc = "Go: media mount" },

      # <Space>f - Find/Search
      { on = [ "<Space>", "f" ], run = "filter --smart", desc = "Filter" },
      { on = [ "<Space>", "/" ], run = "search --via=rg", desc = "Find: content (ripgrep)" },
      { on = [ "<Space>", "n" ], run = 'search --via=fd --args="--type f"', desc = "Find: files by name" },
      { on = [ "<Space>", "<Space>" ], run = "plugin zoxide", desc = "Zoxide jump" },

      # Filter
      { on = [ "f" ], run = "filter --smart", desc = "Filter" },

      # <Space>s - Sort
      { on = [ "<Space>", "s", "n" ], run = "sort natural", desc = "Sort: natural" },
      { on = [ "<Space>", "s", "a" ], run = "sort alphabetical", desc = "Sort: alphabetical" },
      { on = [ "<Space>", "s", "s" ], run = "sort size", desc = "Sort: size" },
      { on = [ "<Space>", "s", "m" ], run = "sort mtime", desc = "Sort: modified" },
      { on = [ "<Space>", "s", "c" ], run = "sort btime", desc = "Sort: created" },
      { on = [ "<Space>", "s", "e" ], run = "sort extension", desc = "Sort: extension" },
      { on = [ "<Space>", "s", "r" ], run = "sort --reverse", desc = "Sort: reverse" },

      # <Space>t - Tabs
      { on = [ "<Space>", "t", "n" ], run = "tab_create --current", desc = "Tab: new" },
      { on = [ "<Space>", "t", "c" ], run = "tab_close", desc = "Tab: close" },
      { on = [ "<Space>", "t", "o" ], run = "tab_close --all", desc = "Tab: close others" },
      { on = [ "<Space>", "t", "1" ], run = "tab_switch 0", desc = "Tab: 1" },
      { on = [ "<Space>", "t", "2" ], run = "tab_switch 1", desc = "Tab: 2" },
      { on = [ "<Space>", "t", "3" ], run = "tab_switch 2", desc = "Tab: 3" },
      { on = [ "<Space>", "t", "4" ], run = "tab_switch 3", desc = "Tab: 4" },
      { on = [ "<Tab>" ], run = "tab_switch 1 --relative", desc = "Next tab" },
      { on = [ "<S-Tab>" ], run = "tab_switch -1 --relative", desc = "Prev tab" },

      # <Space>w - Window/View (linemodes)
      { on = [ "<Space>", "w", "s" ], run = "linemode size", desc = "View: sizes" },
      { on = [ "<Space>", "w", "p" ], run = "linemode permissions", desc = "View: permissions" },
      { on = [ "<Space>", "w", "m" ], run = "linemode mtime", desc = "View: modified time" },
      { on = [ "<Space>", "w", "c" ], run = "linemode btime", desc = "View: created time" },
      { on = [ "<Space>", "w", "n" ], run = "linemode none", desc = "View: clean" },

      # <Space>y - Yank/Copy paths
      { on = [ "<Space>", "y", "p" ], run = "copy path", desc = "Copy: full path" },
      { on = [ "<Space>", "y", "n" ], run = "copy filename", desc = "Copy: filename" },
      { on = [ "<Space>", "y", "d" ], run = "copy dirname", desc = "Copy: directory" },

      # <Space>c - Chmod
      { on = [ "<Space>", "c" ], run = "plugin chmod", desc = "Change permissions" },

      # <Space>a - Select all
      { on = [ "<Space>", "a" ], run = "toggle_all --state=on", desc = "Select all" },

      # ══════════════════════════════════════════════════════════════════
      # CORE VIM MOTIONS
      # ══════════════════════════════════════════════════════════════════
      { on = [ "k" ], run = "arrow -1", desc = "Move up" },
      { on = [ "j" ], run = "arrow 1", desc = "Move down" },
      { on = [ "h" ], run = "leave", desc = "Go back/parent" },
      { on = [ "l" ], run = "enter", desc = "Enter/Open" },
      { on = [ "-" ], run = "leave", desc = "Parent directory" },
      { on = [ "<C-u>" ], run = "arrow -50%", desc = "Half page up" },
      { on = [ "<C-d>" ], run = "arrow 50%", desc = "Half page down" },
      { on = [ "<C-b>" ], run = "arrow -100%", desc = "Page up" },
      { on = [ "<C-f>" ], run = "arrow 100%", desc = "Page down" },
      { on = [ "<Enter>" ], run = "open", desc = "Open" },
      { on = [ "q" ], run = "quit", desc = "Quit" },
      { on = [ "<Esc>" ], run = "escape", desc = "Cancel/Clear" },

      # ══════════════════════════════════════════════════════════════════
      # SELECTION (vim visual mode style)
      # ══════════════════════════════════════════════════════════════════
      { on = [ "v" ], run = "toggle", desc = "Toggle select" },
      { on = [ "V" ], run = "toggle_all", desc = "Toggle all" },
      { on = [ "J" ], run = [ "toggle", "arrow 1" ], desc = "Select & down" },
      { on = [ "K" ], run = [ "arrow -1", "toggle" ], desc = "Up & select" },
      { on = [ "U" ], run = "escape --select", desc = "Clear selection" },

      # ══════════════════════════════════════════════════════════════════
      # FILE OPERATIONS (vim-inspired)
      # ══════════════════════════════════════════════════════════════════
      # Yank/Copy
      { on = [ "y", "y" ], run = "yank", desc = "Yank (copy)" },
      { on = [ "y" ], run = "yank", desc = "Yank (copy)" },

      # Delete
      { on = [ "d", "d" ], run = "remove", desc = "Delete (to trash)" },
      { on = [ "d", "D" ], run = "remove --permanently", desc = "Delete permanently" },

      # Cut (like vim's d but for moving)
      { on = [ "x" ], run = "yank --cut", desc = "Cut" },

      # Paste
      { on = [ "p" ], run = "paste", desc = "Paste here" },
      { on = [ "P" ], run = [ "enter", "paste", "leave" ], desc = "Paste into hovered dir" },

      # Create/Rename
      { on = [ "o" ], run = "create", desc = "Create file/dir" },
      { on = [ "O" ], run = "create --dir", desc = "Create directory" },
      { on = [ "r" ], run = "rename --cursor=before_ext", desc = "Rename" },
      { on = [ "R" ], run = "rename", desc = "Rename (full)" },

      # Links
      { on = [ "s" ], run = "link", desc = "Symlink" },
      { on = [ "S" ], run = "link --relative", desc = "Relative symlink" },

      # ══════════════════════════════════════════════════════════════════
      # QUICK ACCESS
      # ══════════════════════════════════════════════════════════════════
      { on = [ "z" ], run = "plugin zoxide", desc = "Zoxide jump" },
      { on = [ "Z" ], run = "plugin fzf", desc = "FZF jump" },
      { on = [ "," ], run = "plugin bookmarks", desc = "Bookmarks" },
      { on = [ "." ], run = "hidden toggle", desc = "Toggle hidden" },
      { on = [ "i" ], run = "inspect", desc = "Inspect" },
      { on = [ "?" ], run = "help", desc = "Help" },
      { on = [ "!" ], run = "shell --block --confirm", desc = "Shell command" },
      { on = [ ":" ], run = "shell --block --confirm", desc = "Shell (vim-style)" },
      { on = [ "$" ], run = "shell --interactive", desc = "Open shell here" },
      { on = [ "<C-s>" ], run = "shell --interactive", desc = "Open shell here" },

      # ══════════════════════════════════════════════════════════════════
      # PREVIEW
      # ══════════════════════════════════════════════════════════════════
      { on = [ "<C-j>" ], run = "seek 5", desc = "Preview: down" },
      { on = [ "<C-k>" ], run = "seek -5", desc = "Preview: up" },
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
      { on = [ "<C-a>" ], run = "move 0", desc = "Start of line" },
      { on = [ "<C-e>" ], run = "move 999", desc = "End of line" },
      { on = [ "<C-f>" ], run = "move 1", desc = "Forward char" },
      { on = [ "<C-b>" ], run = "move -1", desc = "Backward char" },
      { on = [ "<C-w>" ], run = "backward_kill_word", desc = "Delete word back" },
      { on = [ "<C-u>" ], run = "kill_line", desc = "Clear line" },
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
