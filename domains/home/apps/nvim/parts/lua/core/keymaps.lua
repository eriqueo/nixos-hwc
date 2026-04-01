-- domains/home/apps/nvim/parts/lua/core/keymaps.lua
vim.g.mapleader = " "
vim.g.maplocalleader = " "
local map = vim.keymap.set

map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

map("v", "<", "<gv")
map("v", ">", ">gv")
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- GO / NAV
map("n", "<leader>gh", "<cmd>cd ~<cr>", { desc = "Go: home" })
map("n", "<leader>gc", "<cmd>cd ~/.config<cr>", { desc = "Go: config" })
map("n", "<leader>gn", "<cmd>cd ~/.nixos<cr>", { desc = "Go: nixos" })
map("n", "<leader>gd", "<cmd>cd ~/Downloads<cr>", { desc = "Go: downloads" })
map("n", "<leader>go", "<cmd>cd ~/Documents<cr>", { desc = "Go: documents" })
map("n", "<leader>gr", "<cmd>cd /<cr>", { desc = "Go: root" })

-- FIND / SEARCH
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find: files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Find: grep content" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Find: buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Find: help" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Find: recent files" })
map("n", "<leader>fc", "<cmd>Telescope commands<cr>", { desc = "Find: commands" })
map("n", "<leader>fk", "<cmd>Telescope keymaps<cr>", { desc = "Find: keymaps" })
map("n", "<leader>fn", function() require("telescope.builtin").find_files({ cwd = "~/.nixos", hidden = true }) end, { desc = "Find: nixos files" })
map("n", "<leader>fs", function() require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config") }) end, { desc = "Find: neovim config" })

-- SESSION / TOGGLES
map("n", "<leader>ss", "<cmd>mksession! Session.vim<cr>", { desc = "Session: save" })
map("n", "<leader>sl", "<cmd>source Session.vim<cr>", { desc = "Session: load" })
map("n", "<leader>sr", "<cmd>Telescope resume<cr>", { desc = "Search: resume" })
map("n", "<leader>sw", "<cmd>lua vim.wo.wrap = not vim.wo.wrap<cr>", { desc = "Toggle: wrap" })

-- TOGGLE / TABS
map("n", "<leader>th", "<cmd>set hlsearch!<cr>", { desc = "Toggle: highlight search" })
map("n", "<leader>tn", "<cmd>set number!<cr>", { desc = "Toggle: line numbers" })
map("n", "<leader>tr", "<cmd>set relativenumber!<cr>", { desc = "Toggle: relative numbers" })
map("n", "<leader>ts", "<cmd>set spell!<cr>", { desc = "Toggle: spell check" })
map("n", "<leader>tw", "<cmd>set wrap!<cr>", { desc = "Toggle: word wrap" })
map("n", "<leader>tt", "<cmd>tabnew<cr>", { desc = "Tab: new" })
map("n", "<leader>tc", "<cmd>tabclose<cr>", { desc = "Tab: close" })
map("n", "<leader>t1", "1gt", { desc = "Tab: 1" })
map("n", "<leader>t2", "2gt", { desc = "Tab: 2" })
map("n", "<leader>t3", "3gt", { desc = "Tab: 3" })
map("n", "<leader>t4", "4gt", { desc = "Tab: 4" })

-- YANK / CUT / PASTE (lowercase after leader)
map({ "n", "x" }, "<leader>Y", '"+y', { desc = "Yank: to system clipboard" })
map("n", "<leader>Yy", '"+yy', { desc = "Yank: line to clipboard" })
map({ "n", "x" }, "<leader>x", '"+d', { desc = "Cut: to system clipboard" })
map({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste: from system clipboard" })
map("n", "<leader>yp", "<cmd>let @+=expand('%:p')<cr>", { desc = "Yank: file path" })
map("n", "<leader>yn", "<cmd>let @+=expand('%:t')<cr>", { desc = "Yank: filename" })
map("n", "<leader>yd", "<cmd>let @+=expand('%:h')<cr>", { desc = "Yank: directory" })

-- DELETE / CLEANUP
map({ "n", "v" }, "<leader>dd", [["_d]], { desc = "Delete: to black hole" })
map("n", "<leader>db", "<cmd>bd<cr>", { desc = "Delete: buffer" })
map("n", "<leader>dw", "<cmd>%s/\\s\\+$//e<cr>", { desc = "Delete: trailing whitespace" })

-- WINDOW / VIEW
map("n", "<leader>wv", "<C-w>v", { desc = "Window: vertical split" })
map("n", "<leader>ws", "<C-w>s", { desc = "Window: horizontal split" })
map("n", "<leader>wq", "<C-w>q", { desc = "Window: close" })
map("n", "<leader>wo", "<C-w>o", { desc = "Window: close others" })
map("n", "<leader>w=", "<C-w>=", { desc = "Window: equal size" })
map("n", "<leader>w+", "<C-w>+", { desc = "Window: increase height" })
map("n", "<leader>w-", "<C-w>-", { desc = "Window: decrease height" })
map("n", "<leader>w>", "<C-w>>", { desc = "Window: increase width" })
map("n", "<leader>w<", "<C-w><", { desc = "Window: decrease width" })

-- BUFFERS
map("n", "<leader>bb", "<cmd>Telescope buffers<cr>", { desc = "Buffer: list" })
map("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "Buffer: next" })
map("n", "<leader>bp", "<cmd>bprev<cr>", { desc = "Buffer: previous" })
map("n", "<leader>bd", "<cmd>bd<cr>", { desc = "Buffer: delete" })
map("n", "<leader>ba", "<cmd>%bd|e#|bd#<cr>", { desc = "Buffer: delete all others" })
map("n", "<leader>bl", "<cmd>blast<cr>", { desc = "Buffer: last" })
map("n", "<leader>bf", "<cmd>bfirst<cr>", { desc = "Buffer: first" })

-- OPEN / OIL
map("n", "<leader>ov", "<cmd>Oil<cr>", { desc = "Open: file explorer (Oil)" })
map("n", "<leader>on", "<cmd>Oil ~/.nixos<cr>", { desc = "Open: nixos config" })
map("n", "<leader>oc", "<cmd>Oil ~/.config<cr>", { desc = "Open: config dir" })
map("n", "<leader>oh", "<cmd>Oil ~<cr>", { desc = "Open: home dir" })

-- QUICK SINGLE KEYS
map("n", "o", "o<esc>", { desc = "Open: new line below" })
map("n", "O", "O<esc>", { desc = "Open: new line above" })

-- REPLACE WORD UNDER CURSOR
map("n", "<leader>S", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Replace: word under cursor" })

-- SELECT ALL
map("n", "<leader>a", "ggVG", { silent = true, desc = "Select all" })

-- SUDO WRITE
vim.api.nvim_create_user_command("W", function()
  vim.cmd("write !sudo tee % > /dev/null")
  vim.cmd("edit!")
end, { desc = "Write: with sudo" })
