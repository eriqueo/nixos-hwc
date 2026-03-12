-- domains/home/apps/nvim/parts/lua/plugins/treesitter.lua
require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "lua",
    "vim",
    "vimdoc",
    "query",
    "nix",
    "python",
    "javascript",
    "typescript",
    "html",
    "css",
    "json",
    "markdown",
    "markdown_inline",
    "bash",
    "c",
    "rust",
    "go",
  },

  sync_install = false,
  auto_install = true,

  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },

  indent = {
    enable = true,
  },

  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "gnn",
      node_incremental = "grn",
      scope_incremental = "grc",
      node_decremental = "grm",
    },
  },
})
