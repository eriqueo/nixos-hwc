# domains/home/apps/yazi/parts/keymap.nix
{
  # Keymap configuration for Yazi
  "yazi/keymap.toml" = {
    text = ''
      # ~/.config/yazi/keymap.toml
      [mgr]
keymap = [
  # Space-leader: GO/NAV
  { on = [ "<Space>", "g", "h" ], run = "cd ~", desc = "Go: home" },
  { on = [ "<Space>", "g", "c" ], run = "cd ~/.config", desc = "Go: config" },
  { on = [ "<Space>", "g", "n" ], run = "cd ~/.nixos", desc = "Go: nixos" },
  { on = [ "<Space>", "g", "d" ], run = "cd ~/Downloads", desc = "Go: downloads" },
  { on = [ "<Space>", "g", "D" ], run = "cd ~/Documents", desc = "Go: documents" },
  { on = [ "<Space>", "g", "p" ], run = "cd ~/Pictures", desc = "Go: pictures" },
  { on = [ "<Space>", "g", "v" ], run = "cd ~/Videos", desc = "Go: videos" },
  { on = [ "<Space>", "g", "r" ], run = "cd /", desc = "Go: root" },
  { on = [ "<Space>", "g", "t" ], run = "cd /tmp", desc = "Go: temp" },
  { on = [ "<Space>", "g", "g" ], run = "arrow top", desc = "Go: top" },
  { on = [ "<Space>", "g", "G" ], run = "arrow bot", desc = "Go: bottom" },

  # Space-leader: FIND/SEARCH
  { on = [ "<Space>", "f", "f" ], run = "filter", desc = "Find: filter files" },
  { on = [ "<Space>", "f", "n" ], run = 'search --via=fd --args="--type f"', desc = "Find: by name (files only)" },
  { on = [ "<Space>", "f", "c" ], run = "search --via=rg", desc = "Find: content (ripgrep)" },
  { on = [ "<Space>", "f", "z" ], run = "plugin fzf", desc = "Find: fzf (plugin)" },
  { on = [ "<Space>", "f", "d" ], run = "search --via=fd", desc = "Find: fd search" },
  { on = [ "<Space>", "f", "s" ], run = "escape --search", desc = "Find: stop search" },

  # Space-leader: SORT
  { on = [ "<Space>", "s", "n" ], run = "sort natural", desc = "Sort: natural" },
  { on = [ "<Space>", "s", "a" ], run = "sort alphabetical", desc = "Sort: alphabetical" },
  { on = [ "<Space>", "s", "s" ], run = "sort size", desc = "Sort: size" },
  { on = [ "<Space>", "s", "m" ], run = "sort mtime", desc = "Sort: modified (mtime)" },
  { on = [ "<Space>", "s", "c" ], run = "sort btime", desc = "Sort: created (btime)" },
  { on = [ "<Space>", "s", "e" ], run = "sort extension", desc = "Sort: extension" },
  { on = [ "<Space>", "s", "r" ], run = "sort --reverse", desc = "Sort: reverse" },

  # Space-leader: TOGGLE/TABS
  { on = [ "<Space>", "t", "h" ], run = "hidden toggle", desc = "Toggle: hidden files" },
  { on = [ "<Space>", "t", "p" ], run = "plugin toggle-view", desc = "Toggle: preview (plugin)" },
  { on = [ "<Space>", "t", "n" ], run = "tab_create --current", desc = "Tab: new (here)" },
  { on = [ "<Space>", "t", "c" ], run = "tab_close", desc = "Tab: close" },
  { on = [ "<Space>", "t", "1" ], run = "tab_switch 0", desc = "Tab: 1" },
  { on = [ "<Space>", "t", "2" ], run = "tab_switch 1", desc = "Tab: 2" },
  { on = [ "<Space>", "t", "3" ], run = "tab_switch 2", desc = "Tab: 3" },
  { on = [ "<Space>", "t", "4" ], run = "tab_switch 3", desc = "Tab: 4" },

  # Space-leader: WINDOW/VIEW
  { on = [ "<Space>", "w", "m" ], run = "linemode size", desc = "Window: show sizes" },
  { on = [ "<Space>", "w", "p" ], run = "linemode permissions", desc = "Window: show permissions" },

  # Mode-less bulk selection
  { on = [ "J" ], run = [ "toggle", "arrow 1" ], desc = "Select & move down" },
  { on = [ "K" ], run = [ "arrow -1", "toggle" ], desc = "Move up & toggle" },
  { on = [ "t" ], run = "toggle", desc = "Toggle hovered" },
  { on = [ "A" ], run = "toggle_all --state=on", desc = "Select all (visible)" },
  { on = [ "<Space>", "a" ], run = "toggle_all --state=on", desc = "Select all (leader)" },
  { on = [ "U" ], run = "escape --select", desc = "Unselect all" },

  # Copy / Cut / Paste
  { on = [ "y" ], run = "yank", desc = "Copy selection/hovered" },
  { on = [ "C" ], run = "yank", desc = "Copy (alias)" },
  { on = [ "X" ], run = "yank --cut", desc = "Cut selection/hovered" },
  { on = [ "p" ], run = "paste", desc = "Paste here" },
  { on = [ "P" ], run = [ "enter", "paste", "leave" ], desc = "Paste into hovered dir & return" },

  # Single-key basics
  { on = [ "o" ], run = "create", desc = "Create file/dir" },
  { on = [ "O" ], run = "create --dir", desc = "Create directory" },
  { on = [ "r" ], run = "rename", desc = "Rename" },
  { on = [ "i" ], run = "inspect", desc = "Inspect file" },
  { on = [ "z" ], run = "plugin zoxide", desc = "Jump with zoxide (plugin)" },
  { on = [ "." ], run = "hidden toggle", desc = "Toggle hidden" },
  { on = [ "?" ], run = "help", desc = "Help" },

  # Delete
  { on = [ "d", "d" ], run = "remove", desc = "Delete current file" },
  { on = [ "d", "D" ], run = "remove --permanently", desc = "Delete permanently" },

  # Vim-ish navigation
  { on = [ "k" ], run = "arrow -1", desc = "Move up" },
  { on = [ "j" ], run = "arrow 1", desc = "Move down" },
  { on = [ "h" ], run = "leave", desc = "Go back" },
  { on = [ "l" ], run = "enter", desc = "Enter/Open" },
  { on = [ "g", "g" ], run = "arrow top", desc = "Go to top" },
  { on = [ "G" ], run = "arrow bot", desc = "Go to bottom" },
  { on = [ "<C-u>" ], run = "arrow -50%", desc = "Half page up" },
  { on = [ "<C-d>" ], run = "arrow 50%", desc = "Half page down" },
  { on = [ "<Enter>" ], run = "open", desc = "Open" },
  { on = [ "q" ], run = "quit", desc = "Quit" }
]

[tasks]
keymap = [
  { on = [ "<Esc>" ], run = "close", desc = "Close" },
  { on = [ "q" ], run = "close", desc = "Close" },
  { on = [ "k" ], run = "arrow -1", desc = "Up" },
  { on = [ "j" ], run = "arrow 1", desc = "Down" }
]

[input]
prepend_keymap = [
  { on = [ "<C-a>" ], run = "move 0", desc = "Start of line" },
  { on = [ "<C-e>" ], run = "move 999", desc = "End of line" },
  { on = [ "<C-f>" ], run = "move 1", desc = "Forward char" },
  { on = [ "<C-b>" ], run = "move -1", desc = "Backward char" },
  { on = [ "<Enter>" ], run = "close --submit", desc = "Submit" },
  { on = [ "<Esc>" ], run = "close", desc = "Cancel" }
]
    '';
  };
}
