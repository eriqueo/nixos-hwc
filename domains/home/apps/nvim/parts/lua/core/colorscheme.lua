-- domains/home/apps/nvim/parts/lua/core/colorscheme.lua
-- Configure colorscheme using Deep Nord color palette

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
  palette_overrides = {
    -- Deep Nord color palette
    bright_green = "#a9b665",
    bright_red = "#ea6962",
    bright_blue = "#7daea3",
    bright_yellow = "#d8a657",
    bright_purple = "#d3869b",
    bright_aqua = "#89b482",
  },
  overrides = {
    -- Core colors from Deep Nord palette
    Normal = {bg = "#282828", fg = "#d4be98"},
    Comment = {fg = "#a89984", italic = true},
    Function = {fg = "#d8a657", bold = true},
    Keyword = {fg = "#ea6962", bold = true},
    String = {fg = "#a9b665"},
    Number = {fg = "#d3869b"},
    Boolean = {fg = "#d3869b"},
    Type = {fg = "#7daea3", bold = true},
    Visual = {bg = "#45403d"},
    CursorLine = {bg = "#32302f"},
    LineNr = {fg = "#665c54"},
    CursorLineNr = {fg = "#d4be98", bold = true},
    StatusLine = {fg = "#d4be98", bg = "#45403d", bold = true},

    -- Treesitter-specific highlight groups
    ["@function"] = {fg = "#d8a657", bold = true},
    ["@function.call"] = {fg = "#d8a657"},
    ["@function.builtin"] = {fg = "#d8a657", bold = true},
    ["@method"] = {fg = "#d8a657", bold = true},
    ["@method.call"] = {fg = "#d8a657"},

    ["@keyword"] = {fg = "#ea6962", bold = true},
    ["@keyword.function"] = {fg = "#ea6962", bold = true},
    ["@keyword.operator"] = {fg = "#ea6962"},
    ["@keyword.return"] = {fg = "#ea6962", bold = true},
    ["@keyword.conditional"] = {fg = "#ea6962", bold = true},
    ["@keyword.repeat"] = {fg = "#ea6962", bold = true},

    ["@string"] = {fg = "#a9b665"},
    ["@string.regex"] = {fg = "#a9b665", italic = true},
    ["@string.escape"] = {fg = "#d8a657"},

    ["@number"] = {fg = "#d3869b"},
    ["@boolean"] = {fg = "#d3869b"},
    ["@float"] = {fg = "#d3869b"},

    ["@type"] = {fg = "#7daea3", bold = true},
    ["@type.builtin"] = {fg = "#7daea3", bold = true},
    ["@type.definition"] = {fg = "#7daea3", bold = true},

    ["@variable"] = {fg = "#d4be98"},
    ["@variable.builtin"] = {fg = "#ea6962"},
    ["@parameter"] = {fg = "#d4be98"},

    ["@constant"] = {fg = "#d3869b", bold = true},
    ["@constant.builtin"] = {fg = "#d3869b", bold = true},
    ["@constant.macro"] = {fg = "#ea6962"},

    ["@operator"] = {fg = "#ea6962"},
    ["@punctuation"] = {fg = "#d4be98"},
    ["@punctuation.bracket"] = {fg = "#d4be98"},
    ["@punctuation.delimiter"] = {fg = "#d4be98"},

    ["@comment"] = {fg = "#a89984", italic = true},
    ["@comment.todo"] = {fg = "#d8a657", bold = true},
    ["@comment.warning"] = {fg = "#ea6962", bold = true},
    ["@comment.note"] = {fg = "#7daea3", bold = true},

    -- Markdown-specific
    ["@markup.heading.1"] = {fg = "#ea6962", bold = true},
    ["@markup.heading.2"] = {fg = "#d8a657", bold = true},
    ["@markup.heading.3"] = {fg = "#a9b665", bold = true},
    ["@markup.heading.4"] = {fg = "#7daea3", bold = true},
    ["@markup.heading.5"] = {fg = "#d3869b", bold = true},
    ["@markup.heading.6"] = {fg = "#89b482", bold = true},
    ["@markup.strong"] = {fg = "#d4be98", bold = true},
    ["@markup.italic"] = {fg = "#d4be98", italic = true},
    ["@markup.link"] = {fg = "#7daea3", underline = true},
    ["@markup.link.url"] = {fg = "#89b482"},
    ["@markup.raw"] = {fg = "#a9b665"},
    ["@markup.raw.block"] = {fg = "#a9b665"},

    -- LSP diagnostics
    DiagnosticError = {fg = "#ea6962"},
    DiagnosticWarn = {fg = "#d8a657"},
    DiagnosticInfo = {fg = "#7daea3"},
    DiagnosticHint = {fg = "#89b482"},

    -- Additional UI elements
    FloatBorder = {fg = "#7daea3"},
    Pmenu = {bg = "#32302f", fg = "#d4be98"},
    PmenuSel = {bg = "#45403d", fg = "#d4be98"},
  },
  dim_inactive = false,
  transparent_mode = false,
})

vim.cmd("colorscheme gruvbox")

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, "TelescopeNormal", { bg = "#282828" })
    vim.api.nvim_set_hl(0, "TelescopeBorder", { fg = "#7daea3" })
    vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#7daea3" })
  end,
})
