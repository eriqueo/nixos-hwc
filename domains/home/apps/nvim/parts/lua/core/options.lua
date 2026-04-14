-- domains/home/apps/nvim/parts/lua/core/options.lua
local opt = vim.opt

-- Line numbers
opt.relativenumber = true
opt.number = true

-- Search settings
opt.hlsearch = false
opt.incsearch = true

-- Mouse & clipboard
opt.mouse = "a"
opt.clipboard = "unnamedplus"

-- Indentation
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true
opt.breakindent = true

-- File handling
opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.undodir = os.getenv("HOME") .. "/.vim/undodir"

-- Search behavior
opt.ignorecase = true
opt.smartcase = true

-- UI
opt.updatetime = 50
opt.signcolumn = "yes"
opt.termguicolors = true
opt.scrolloff = 8
opt.isfname:append("@-@")

-- Folding
opt.foldcolumn = "1"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true

-- Split behavior
opt.splitbelow = true
opt.splitright = true

-- Font configuration
opt.guifont = "Fira Code:h16"
