# domains/home/apps/yazi/parts/keymap.nix
{
  # Keymap configuration for Yazi
  "yazi/keymap.toml" = {
    text = ''
    # ~/.config/yazi/keymap.toml
    [mgr]
    keymap = [
      # Space-leader: GO/NAV (Updated with numbered shortcuts)
      { on = [ "<Space>", "g", "h" ], run = "cd ~", desc = "Go: home" },
      { on = [ "<Space>", "g", "c" ], run = "cd ~/.config", desc = "Go: config" },
      { on = [ "<Space>", "g", "n" ], run = "cd ~/.nixos", desc = "Go: nixos" },
      { on = [ "<Space>", "g", "r" ], run = "cd /", desc = "Go: root" },
      { on = [ "<Space>", "g", "t" ], run = "cd /tmp", desc = "Go: temp" },
      
      # NEW: Numbered directory shortcuts (adjust paths to match your setup)
      { on = [ "<Space>", "g", "0" ], run = "cd ~/00_inbox", desc = "Go: 0_dotfiles" },
      { on = [ "<Space>", "g", "1" ], run = "cd ~/01_hwc", desc = "Go: 1_documents" },
      { on = [ "<Space>", "g", "2" ], run = "cd ~/02_personal", desc = "Go: 2_downloads" },
      { on = [ "<Space>", "g", "3" ], run = "cd ~/03_tech", desc = "Go: 3_pictures" },
      { on = [ "<Space>", "g", "4" ], run = "cd ~/04_reference", desc = "Go: 4_videos" },
      { on = [ "<Space>", "g", "5" ], run = "cd ~/05_media", desc = "Go: 5_projects" },
      { on = [ "<Space>", "g", "6" ], run = "cd ~/06_archive", desc = "Go: 6_archive" },
      { on = [ "<Space>", "g", "7" ], run = "cd ~/07_temp", desc = "Go: 7_temp" },
      { on = [ "<Space>", "g", "8" ], run = "cd ~/08_misc", desc = "Go: 8_misc" },
      { on = [ "<Space>", "g", "9" ], run = "cd ~/900_vaults", desc = "Go: 9_vaults" },
    
      # Keep your existing letter-based shortcuts for compatibility
      { on = [ "<Space>", "g", "d" ], run = "cd ~/00_inbox", desc = "Go: downloads" },
      { on = [ "<Space>", "g", "n" ], run = "cd ~/.nixos", desc = "Go: documents" },
      { on = [ "<Space>", "g", "p" ], run = "cd ~/05_media/pictures", desc = "Go: pictures" },
      { on = [ "<Space>", "g", "v" ], run = "cd ~/900_vaults", desc = "Go: vaults" },
    
      # Space-leader: FIND/SEARCH (keeping your existing setup)
      { on = [ "<Space>", "f", "f" ], run = "filter", desc = "Find: filter files" },
      { on = [ "<Space>", "f", "n" ], run = 'search --via=fd --args="--type f"', desc = "Find: by name (files only)" },
      { on = [ "<Space>", "f", "c" ], run = "search --via=rg", desc = "Find: content (ripgrep)" },
      { on = [ "<Space>", "f", "z" ], run = "plugin fzf", desc = "Find: fzf (plugin)" },
      { on = [ "<Space>", "f", "d" ], run = "search --via=fd", desc = "Find: fd search" },
      { on = [ "<Space>", "f", "s" ], run = "escape --search", desc = "Find: stop search" },
    
      # Space-leader: SORT (keeping your existing setup)
      { on = [ "<Space>", "s", "n" ], run = "sort natural", desc = "Sort: natural" },
      { on = [ "<Space>", "s", "a" ], run = "sort alphabetical", desc = "Sort: alphabetical" },
      { on = [ "<Space>", "s", "s" ], run = "sort size", desc = "Sort: size" },
      { on = [ "<Space>", "s", "m" ], run = "sort mtime", desc = "Sort: modified (mtime)" },
      { on = [ "<Space>", "s", "c" ], run = "sort btime", desc = "Sort: created (btime)" },
      { on = [ "<Space>", "s", "e" ], run = "sort extension", desc = "Sort: extension" },
      { on = [ "<Space>", "s", "r" ], run = "sort --reverse", desc = "Sort: reverse" },
    
      # Space-leader: TOGGLE/TABS (keeping your existing setup)
      { on = [ "<Space>", "t", "h" ], run = "hidden toggle", desc = "Toggle: hidden files" },
      { on = [ "<Space>", "t", "p" ], run = "plugin toggle-view", desc = "Toggle: preview (plugin)" },
      { on = [ "<Space>", "t", "n" ], run = "tab_create --current", desc = "Tab: new (here)" },
      { on = [ "<Space>", "t", "c" ], run = "tab_close", desc = "Tab: close" },
      { on = [ "<Space>", "t", "1" ], run = "tab_switch 0", desc = "Tab: 1" },
      { on = [ "<Space>", "t", "2" ], run = "tab_switch 1", desc = "Tab: 2" },
      { on = [ "<Space>", "t", "3" ], run = "tab_switch 2", desc = "Tab: 3" },
      { on = [ "<Space>", "t", "4" ], run = "tab_switch 3", desc = "Tab: 4" },
    
      # Space-leader: WINDOW/VIEW (keeping your existing setup + adding our new ones)
      { on = [ "<Space>", "w", "m" ], run = "linemode size", desc = "Window: show sizes" },
      { on = [ "<Space>", "w", "p" ], run = "linemode permissions", desc = "Window: show permissions" },
      { on = [ "<Space>", "w", "s" ], run = "split --ratio=0.5 --direction=horizontal", desc = "Window: horizontal split" },
      { on = [ "<Space>", "w", "v" ], run = "split --ratio=0.5 --direction=vertical", desc = "Window: vertical split" },
    
      # Mode-less bulk selection (keeping your existing setup)
      { on = [ "J" ], run = [ "toggle", "arrow 1" ], desc = "Select & move down" },
      { on = [ "K" ], run = [ "arrow -1", "toggle" ], desc = "Move up & toggle" },
      { on = [ "t" ], run = "toggle", desc = "Toggle hovered" },
      { on = [ "A" ], run = "toggle_all --state=on", desc = "Select all (visible)" },
      { on = [ "<Space>", "a" ], run = "toggle_all --state=on", desc = "Select all (leader)" },
      { on = [ "U" ], run = "escape --select", desc = "Unselect all" },
    
      # Copy / Cut / Paste (keeping your existing setup)
      { on = [ "y" ], run = "yank", desc = "Copy selection/hovered" },
      { on = [ "C" ], run = "yank", desc = "Copy (alias)" },
      { on = [ "X" ], run = "yank --cut", desc = "Cut selection/hovered" },
      { on = [ "p" ], run = "paste", desc = "Paste here" },
      { on = [ "P" ], run = [ "enter", "paste", "leave" ], desc = "Paste into hovered dir & return" },
    
      # Single-key basics (keeping your existing setup)
      { on = [ "o" ], run = "create", desc = "Create file/dir" },
      { on = [ "O" ], run = "create --dir", desc = "Create directory" },
      { on = [ "r" ], run = "rename", desc = "Rename" },
      { on = [ "i" ], run = "inspect", desc = "Inspect file" },
      { on = [ "z" ], run = "plugin zoxide", desc = "Jump with zoxide (plugin)" },
      { on = [ "." ], run = "hidden toggle", desc = "Toggle hidden" },
      { on = [ "?" ], run = "help", desc = "Help" },
    
      # Delete (keeping your existing setup)
      { on = [ "d", "d" ], run = "remove", desc = "Delete current file" },
      { on = [ "d", "D" ], run = "remove --permanently", desc = "Delete permanently" },
    
      # Vim-ish navigation (keeping your existing setup)
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
