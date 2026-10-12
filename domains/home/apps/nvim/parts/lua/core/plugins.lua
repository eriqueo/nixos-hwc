-- domains/home/apps/nvim/parts/lua/core/plugins.lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Color scheme
  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    config = function()
      require("gruvbox").setup({
        terminal_colors = true,
        undercurl = true,
        underline = true,
        bold = true,
        italic = {
          strings = true,
          emphasis = true,
          comments = true,
          operators = false,
          folds = true,
        },
        strikethrough = true,
        invert_selection = false,
        invert_signs = false,
        invert_tabline = false,
        invert_intend_guides = false,
        inverse = true,
        contrast = "",
        palette_overrides = {},
        overrides = {},
        dim_inactive = false,
        transparent_mode = false,
      })
      vim.opt.background = "dark"
      vim.cmd.colorscheme("gruvbox")
    end,
  },

  -- Essential dependencies
  { "nvim-lua/plenary.nvim" },
  { "echasnovski/mini.icons", version = false },

  -- File explorer (like NvimTree but simpler)
  {
    "stevearc/oil.nvim",
    config = function()
      require("oil").setup({
        default_file_explorer = true,
        keymaps = {
          ["g?"] = "actions.show_help",
          ["<CR>"] = "actions.select",
          ["<C-v>"] = "actions.select_vsplit",
          ["<C-h>"] = "actions.select_split",
          ["-"] = "actions.parent",
          ["_"] = "actions.open_cwd",
          ["`"] = "actions.cd",
          ["~"] = "actions.tcd",
          ["gs"] = "actions.change_sort",
          ["gx"] = "actions.open_external",
          ["g."] = "actions.toggle_hidden",
        },
      })
    end,
  },

  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      require("plugins.telescope")
      pcall(require("telescope").load_extension, "fzf")
    end,
  },

  -- Primary fuzzy finder (native fzf binary — fast over huge file trees).
  -- Finder keymaps (ff/fg/fb/fn/fs) point here; Telescope kept for the rest.
  {
    "ibhagwan/fzf-lua",
    dependencies = { "echasnovski/mini.icons" },
    config = function()
      require("plugins.fzf-lua")
    end,
  },

  -- Formatting (replaces none-ls)
  {
    "stevearc/conform.nvim",
    lazy = false,
    cmd = { "ConformInfo" },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          lua = { "stylua" },
          nix = { "alejandra" },
          python = { "ruff_format" },
          javascript = { "prettier" },
          typescript = { "prettier" },
          json = { "prettier" },
          yaml = { "prettier" },
          markdown = { "prettier" },
        },
        format_on_save = {
          timeout_ms = 3000,
          lsp_format = "fallback",
        },
      })
    end,
  },

  -- Diagnostics list (workspace-wide problems panel)
  {
    "folke/trouble.nvim",
    dependencies = { "echasnovski/mini.icons" },
    cmd = "Trouble",
    config = function()
      require("trouble").setup()
    end,
  },

  -- Highlight and search TODO/FIXME/HACK comments
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    config = function()
      require("todo-comments").setup()
    end,
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous TODO" },
    },
  },

  -- tuxedo.nvim — floating todo.txt popup (IogaMaster/tuxedo.nvim).
  -- Companion to the tuxedo CLI (hwc.home.apps.tuxedo). Lazy-loaded on the
  -- uses (TODO_FILE is set in the session env) — verify after first launch.
  {
    "IogaMaster/tuxedo.nvim",
    cmd = "Tuxedo",
    config = function()
      require("tuxedo").setup({
        create_todo_file = true,
        width_ratio = 0.95,
        height_ratio = 0.80,
      })
    end,
  },

  -- Harpoon
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup()

      vim.keymap.set("n", "<C-e>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Toggle harpoon menu" })
      vim.keymap.set("n", "<C-S-P>", function() harpoon:list():prev() end, { desc = "Previous harpoon file" })
      vim.keymap.set("n", "<C-S-N>", function() harpoon:list():next() end, { desc = "Next harpoon file" })
    end,
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      -- Neovim 0.10+ built-in treesitter config
      vim.treesitter.language.register("bash", "zsh")

      -- Enable treesitter highlighting
      vim.api.nvim_create_autocmd("FileType", {
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })

      -- Install parsers via TSInstall command if needed
      vim.api.nvim_create_user_command("TSInstallAll", function()
        local parsers = { "lua", "vim", "vimdoc", "query", "nix", "python",
          "javascript", "typescript", "html", "css", "json",
          "markdown", "markdown_inline", "bash", "c", "rust", "go" }
        for _, lang in ipairs(parsers) do
          vim.cmd("TSInstall " .. lang)
        end
      end, {})
    end,
  },

  -- Treesitter text objects (select/move by function, class, etc.)
  -- Uses the new `main`-branch API (the legacy `nvim-treesitter.configs.setup`
  -- entry point was removed in the v1.0 rewrite).
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = "VeryLazy",
    init = function()
      -- Required by the new branch to prevent built-in ftplugin mapping clashes.
      vim.g.no_plugin_maps = true
    end,
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })

      local select = function(query) return function()
        require("nvim-treesitter-textobjects.select").select_textobject(query, "textobjects")
      end end
      local move_next = function(query) return function()
        require("nvim-treesitter-textobjects.move").goto_next_start(query, "textobjects")
      end end
      local move_prev = function(query) return function()
        require("nvim-treesitter-textobjects.move").goto_previous_start(query, "textobjects")
      end end

      local sel_modes = { "x", "o" }
      vim.keymap.set(sel_modes, "af", select("@function.outer"),  { desc = "ts: a function" })
      vim.keymap.set(sel_modes, "if", select("@function.inner"),  { desc = "ts: inner function" })
      vim.keymap.set(sel_modes, "ac", select("@class.outer"),     { desc = "ts: a class" })
      vim.keymap.set(sel_modes, "ic", select("@class.inner"),     { desc = "ts: inner class" })
      vim.keymap.set(sel_modes, "aa", select("@parameter.outer"), { desc = "ts: a parameter" })
      vim.keymap.set(sel_modes, "ia", select("@parameter.inner"), { desc = "ts: inner parameter" })

      local mv_modes = { "n", "x", "o" }
      vim.keymap.set(mv_modes, "]m", move_next("@function.outer"), { desc = "ts: next function" })
      vim.keymap.set(mv_modes, "]]", move_next("@class.outer"),    { desc = "ts: next class" })
      vim.keymap.set(mv_modes, "[m", move_prev("@function.outer"), { desc = "ts: prev function" })
      vim.keymap.set(mv_modes, "[[", move_prev("@class.outer"),    { desc = "ts: prev class" })
    end,
  },

  -- LSP Configuration
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("plugins.lsp")
    end,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      require("plugins.cmp")
    end,
  },

  -- Git integration
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        current_line_blame = false, -- toggle with keymap
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = vim.keymap.set
          local opts = { buffer = bufnr }

          map("n", "]h", gs.next_hunk, vim.tbl_extend("force", opts, { desc = "Next hunk" }))
          map("n", "[h", gs.prev_hunk, vim.tbl_extend("force", opts, { desc = "Previous hunk" }))
        end,
      })
    end,
  },

  -- Status line
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "gruvbox",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },
      })
    end,
  },

  -- Auto pairs
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup()
    end,
  },

  -- Commenting
  {
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end,
  },

  -- Which-key (shows keybindings)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    config = function()
      -- HWC standard popup look (matches the aerc which-key card): a
      -- double-bordered floating card, "key → desc" rows, no per-mapping
      -- icons. Colors come from the generated colorscheme (WhichKey* groups
      -- in parts/appearance.nix) so the red default group colour is gone.
      require("which-key").setup({
        preset = "modern",
        icons = {
          mappings = false,
          separator = "→",
        },
        win = {
          border = "double",
          padding = { 1, 3 },
          title = true,
          title_pos = "left",
        },
        layout = {
          spacing = 4,
          align = "left",
        },
        show_help = false,
      })
    end,
  },

  -- Better notifications
  {
    "rcarriga/nvim-notify",
    config = function()
      vim.notify = require("notify")
    end,
  },

  -- Surround motions
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup()
    end,
  },

  -- Claude Code CLI integration (VS Code-like)
  {
    "coder/claudecode.nvim",
    cmd = { "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeAdd", "ClaudeCodeSend",
      "ClaudeCodeDiffAccept", "ClaudeCodeDiffDeny" },
    dependencies = { "folke/snacks.nvim" },
    config = true,
  },
}, {
  rocks = {
    enabled = false,
  },
  checker = {
    enabled = false,
  },
  change_detection = {
    enabled = false,
  },
})
