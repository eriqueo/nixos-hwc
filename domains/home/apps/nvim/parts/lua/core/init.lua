-- domains/home/apps/nvim/parts/lua/core/init.lua
require("core.options")
require("core.keymaps")
require("core.plugins")
require("core.colorscheme")

-- Add custom filetypes for gopls
vim.filetype.add({
  extension = {
    gowork = "gowork",
    gotmpl = "gotmpl",
  }
})
