-- domains/home/apps/nvim/parts/lua/core/keymaps.lua
vim.g.mapleader = " "
vim.g.maplocalleader = " "
local map = vim.keymap.set

map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- CLAUDE PANE (Alt = Claude movement, distinct mental model)
map("n", "<M-l>", "<C-w>l", { desc = "Claude: enter pane (right window)" })
map("t", "<M-h>", [[<C-\><C-n><C-w>h]], { desc = "Claude: leave pane (back to editor)" })

map("v", "<", "<gv")
map("v", ">", ">gv")
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- QUICK SINGLE KEYS
map("n", "o", "o<esc>", { desc = "Open: new line below" })
map("n", "O", "O<esc>", { desc = "Open: new line above" })

-- SUDO WRITE
vim.api.nvim_create_user_command("W", function()
  vim.cmd("write !sudo tee % > /dev/null")
  vim.cmd("edit!")
end, { desc = "Write: with sudo" })
