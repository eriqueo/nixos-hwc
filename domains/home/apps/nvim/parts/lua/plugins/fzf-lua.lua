-- domains/home/apps/nvim/parts/lua/plugins/fzf-lua.lua
--
-- fzf-lua — primary fuzzy finder. Offloads filtering to the native `fzf`
-- binary (provided via programs.neovim.extraPackages → fzf), so it stays
-- instant even across tens of thousands of files where Telescope's Lua-side
-- result pipeline crawls. Telescope is retained for its non-finder pickers;
-- the file/grep/buffer keymaps point here (see core/keymaps.lua).
local fzf = require("fzf-lua")

fzf.setup({
  -- Gruvbox-friendly, terminal-native UI; no border clutter.
  "default-title",
  fzf_opts = {
    -- Show the longest tail of the path so deep/long filenames stay readable.
    ["--info"] = "inline",
  },
  files = {
    -- fd respects .gitignore by default; --hidden to match the old Telescope
    -- behaviour, excluding the .git dir.
    cmd = "fd --type f --hidden --exclude .git",
  },
  grep = {
    -- rg backing live_grep; hidden but skip the .git dir.
    rg_opts = "--hidden --column --line-number --no-heading --color=always "
      .. "--smart-case --glob=!.git/",
  },
})
