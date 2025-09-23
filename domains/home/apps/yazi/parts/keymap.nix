# domains/home/apps/yazi/parts/keymap.nix
{
  # Keymap configuration for Yazi
  # Defines all universal and single-key bindings.
  "yazi/keymap.toml" = {
    text = ''
      # UNIVERSAL KEYBINDING SYSTEM - YAZI
      # Space-leader based with consistent patterns
      
      [mgr]
      prepend_keymap = [
        # === SPACE LEADER BINDINGS ===
        
        # <Space>g - GO/NAVIGATION
        { on = [ " ", "g", "h" ], run = "cd ~", desc = "Go: home" },
        { on = [ " ", "g", "c" ], run = "cd ~/.config", desc = "Go: config" },
        { on = [ " ", "g", "n" ], run = "cd ~/.nixos", desc = "Go: nixos" },
        { on = [ " ", "g", "d" ], run = "cd ~/Downloads", desc = "Go: downloads" },
        { on = [ " ", "g", "D" ], run = "cd ~/Documents", desc = "Go: documents" },
        { on = [ " ", "g", "p" ], run = "cd ~/Pictures", desc = "Go: pictures" },
        { on = [ " ", "g", "v" ], run = "cd ~/Videos", desc = "Go: videos" },
        { on = [ " ", "g", "r" ], run = "cd /", desc = "Go: root" },
        { on = [ " ", "g", "t" ], run = "cd /tmp", desc = "Go: temp" },
        { on = [ " ", "g", "g" ], run = "arrow -99999999", desc = "Go: top" },
        { on = [ " ", "g", "G" ], run = "arrow 99999999", desc = "Go: bottom" },
        
        # <Space>f - FIND/SEARCH
        { on = [ " ", "f", "f" ], run = "filter", desc = "Find: filter files" },
        { on = [ " ", "f", "n" ], run = "find --type f --name", desc = "Find: by name" },
        { on = [ " ", "f", "c" ], run = "search rg", desc = "Find: content (ripgrep)" },
        { on = [ " ", "f", "z" ], run = "plugin fzf", desc = "Find: fzf" },
        { on = [ " ", "f", "d" ], run = "search fd", desc = "Find: fd search" },
        { on = [ " ", "f", "s" ], run = "search none", desc = "Find: stop search" },
        
        # <Space>s - SORT/SESSION/SYSTEM
        { on = [ " ", "s", "n" ], run = "sort natural", desc = "Sort: by name" },
        { on = [ " ", "s", "s" ], run = "sort size", desc = "Sort: by size" },
        { on = [ " ", "s", "m" ], run = "sort modified", desc = "Sort: by modified" },
        { on = [ " ", "s", "c" ], run = "sort created", desc = "Sort: by created" },
        { on = [ " ", "s", "e" ], run = "sort extension", desc = "Sort: by extension" },
        { on = [ " ", "s", "r" ], run = "sort reverse", desc = "Sort: reverse" },
        
        # <Space>t - TOGGLE/TABS
        { on = [ " ", "t", "h" ], run = "toggle_hidden", desc = "Toggle: hidden files" },
        { on = [ " ", "t", "p" ], run = "toggle_preview", desc = "Toggle: preview" },
        { on = [ " ", "t", "n" ], run = "tab_create --current", desc = "Tab: new" },
        { on = [ " ", "t", "c" ], run = "tab_close", desc = "Tab: close" },
        { on = [ " ", "t", "1" ], run = "tab_switch 0", desc = "Tab: 1" },
        { on = [ " ", "t", "2" ], run = "tab_switch 1", desc = "Tab: 2" },
        { on = [ " ", "t", "3" ], run = "tab_switch 2", desc = "Tab: 3" },
        { on = [ " ", "t", "4" ], run = "tab_switch 3", desc = "Tab: 4" },
        
        # <Space>y - YANK/COPY
        { on = [ " ", "y", "y" ], run = "yank", desc = "Yank: copy files" },
        { on = [ " ", "y", "p" ], run = "shell 'echo %{} | wl-copy'", desc = "Yank: copy path" },
        { on = [ " ", "y", "n" ], run = "shell 'basename %{} | wl-copy'", desc = "Yank: copy filename" },
        
        # <Space>d - DELETE/REMOVE
        { on = [ " ", "d", "d" ], run = "remove", desc = "Delete: to trash" },
        { on = [ " ", "d", "D" ], run = "remove --permanently", desc = "Delete: permanent" },
        { on = [ " ", "d", "x" ], run = "yank --cut", desc = "Delete: cut files" },
        
        # <Space>w - WINDOW/VIEW
        { on = [ " ", "w", "=" ], run = "resize +5", desc = "Window: increase preview" },
        { on = [ " ", "w", "-" ], run = "resize -5", desc = "Window: decrease preview" },
        { on = [ " ", "w", "0" ], run = "resize 50", desc = "Window: reset preview" },
        { on = [ " ", "w", "m" ], run = "linemode size", desc = "Window: show sizes" },
        { on = [ " ", "w", "p" ], run = "linemode permissions", desc = "Window: show permissions" },
        
        # <Space>b - BULK/BUFFERS
        { on = [ " ", "b", "a" ], run = "select_all --state=true", desc = "Bulk: select all" },
        { on = [ " ", "b", "i" ], run = "select_all --state=none", desc = "Bulk: invert selection" },
        { on = [ " ", "b", "n" ], run = "select_all --state=false", desc = "Bulk: select none" },
        { on = [ " ", "b", "p" ], run = "paste", desc = "Bulk: paste" },
        { on = [ " ", "b", "P" ], run = "paste --force", desc = "Bulk: paste force" },
        
        # === QUICK SINGLE-KEY BINDINGS ===
        { on = [ "o" ], run = "create", desc = "Create file/dir" },
        { on = [ "O" ], run = "create --dir", desc = "Create directory" },
        { on = [ "r" ], run = "rename", desc = "Rename" },
        { on = [ "R" ], run = "rename --cursor=before_ext", desc = "Rename (before ext)" },
        { on = [ "i" ], run = "inspect", desc = "Inspect file" },
        { on = [ "z" ], run = "plugin zoxide", desc = "Jump with zoxide" },
        { on = [ "." ], run = "toggle_hidden", desc = "Toggle hidden" },
        { on = [ "?" ], run = "help", desc = "Help" },
      ]
      
      # Default vim navigation (keep these)
      keymap = [
        { on = [ "k" ], run = "arrow -1", desc = "Move up" },
        { on = [ "j" ], run = "arrow 1", desc = "Move down" },
        { on = [ "h" ], run = "leave", desc = "Go back" },
        { on = [ "l" ], run = "enter", desc = "Enter/Open" },
        { on = [ "g", "g" ], run = "arrow -99999999", desc = "Go to top" },
        { on = [ "G" ], run = "arrow 99999999", desc = "Go to bottom" },
        { on = [ "<C-u>" ], run = "arrow -50%", desc = "Half page up" },
        { on = [ "<C-d>" ], run = "arrow 50%", desc = "Half page down" },
        { on = [ "<Enter>" ], run = "open", desc = "Open" },
        { on = [ "<Space>" ], run = [ "select --state=none", "arrow 1" ], desc = "Select toggle" },
        { on = [ "q" ], run = "quit", desc = "Quit" },
      ]
      
      [tasks]
      keymap = [
        { on = [ "<Esc>" ], run = "close", desc = "Close" },
        { on = [ "q" ], run = "close", desc = "Close" },
        { on = [ "k" ], run = "arrow -1", desc = "Up" },
        { on = [ "j" ], run = "arrow 1", desc = "Down" },
      ]
      
      [input]
      keymap = [
        { on = [ "<C-a>" ], run = "move 0", desc = "Start of line" },
        { on = [ "<C-e>" ], run = "move 999", desc = "End of line" },
        { on = [ "<C-f>" ], run = "move 1", desc = "Forward char" },
        { on = [ "<C-b>" ], run = "move -1", desc = "Backward char" },
        { on = [ "<Enter>" ], run = "close --submit", desc = "Submit" },
        { on = [ "<Esc>" ], run = "close", desc = "Cancel" },
      ]
    '';
  };
}
