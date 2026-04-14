# domains/home/apps/nvim/parts/appearance.nix
# Pure function: palette colors → gruvbox.nvim colorscheme.lua content.
# No options, no side-effects.
{ lib, colors }:

let
  c = colors;
  a = c.ansi;
in
{
  colorscheme = ''
    -- Generated from ${c.name or "unknown"} palette
    -- domains/home/apps/nvim/parts/appearance.nix

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
        bright_green  = "#${a.brightGreen}",
        bright_red    = "#${a.brightRed}",
        bright_blue   = "#${a.brightBlue}",
        bright_yellow = "#${a.brightYellow}",
        bright_purple = "#${a.brightMagenta}",
        bright_aqua   = "#${a.brightCyan}",
      },
      overrides = {
        -- Core
        Normal       = {bg = "#${c.bg0}", fg = "#${c.fg1}"},
        Comment      = {fg = "#${c.fg3}", italic = true},
        Function     = {fg = "#${c.accent}", bold = true},
        Keyword      = {fg = "#${c.errorBright}", bold = true},
        String       = {fg = "#${c.success}"},
        Number       = {fg = "#${a.brightMagenta}"},
        Boolean      = {fg = "#${a.brightMagenta}"},
        Type         = {fg = "#${a.brightBlue}", bold = true},
        Visual       = {bg = "#${c.bg3}"},
        CursorLine   = {bg = "#${c.bg2}"},
        LineNr       = {fg = "#${c.fg3}"},
        CursorLineNr = {fg = "#${c.fg1}", bold = true},
        StatusLine   = {fg = "#${c.fg1}", bg = "#${c.bg3}", bold = true},

        -- Treesitter: functions
        ["@function"]         = {fg = "#${c.accent}", bold = true},
        ["@function.call"]    = {fg = "#${c.accent}"},
        ["@function.builtin"] = {fg = "#${c.accent}", bold = true},
        ["@method"]           = {fg = "#${c.accent}", bold = true},
        ["@method.call"]      = {fg = "#${c.accent}"},

        -- Treesitter: keywords
        ["@keyword"]             = {fg = "#${c.errorBright}", bold = true},
        ["@keyword.function"]    = {fg = "#${c.errorBright}", bold = true},
        ["@keyword.operator"]    = {fg = "#${c.errorBright}"},
        ["@keyword.return"]      = {fg = "#${c.errorBright}", bold = true},
        ["@keyword.conditional"] = {fg = "#${c.errorBright}", bold = true},
        ["@keyword.repeat"]      = {fg = "#${c.errorBright}", bold = true},

        -- Treesitter: strings
        ["@string"]        = {fg = "#${c.success}"},
        ["@string.regex"]  = {fg = "#${c.success}", italic = true},
        ["@string.escape"] = {fg = "#${c.warning}"},

        -- Treesitter: literals
        ["@number"]  = {fg = "#${a.brightMagenta}"},
        ["@boolean"] = {fg = "#${a.brightMagenta}"},
        ["@float"]   = {fg = "#${a.brightMagenta}"},

        -- Treesitter: types
        ["@type"]            = {fg = "#${a.brightBlue}", bold = true},
        ["@type.builtin"]    = {fg = "#${a.brightBlue}", bold = true},
        ["@type.definition"] = {fg = "#${a.brightBlue}", bold = true},

        -- Treesitter: identifiers
        ["@variable"]         = {fg = "#${c.fg1}"},
        ["@variable.builtin"] = {fg = "#${c.errorBright}"},
        ["@parameter"]        = {fg = "#${c.fg1}"},

        -- Treesitter: constants
        ["@constant"]         = {fg = "#${a.brightMagenta}", bold = true},
        ["@constant.builtin"] = {fg = "#${a.brightMagenta}", bold = true},
        ["@constant.macro"]   = {fg = "#${c.errorBright}"},

        -- Treesitter: punctuation
        ["@operator"]              = {fg = "#${c.errorBright}"},
        ["@punctuation"]           = {fg = "#${c.fg1}"},
        ["@punctuation.bracket"]   = {fg = "#${c.fg1}"},
        ["@punctuation.delimiter"] = {fg = "#${c.fg1}"},

        -- Treesitter: comments
        ["@comment"]         = {fg = "#${c.fg3}", italic = true},
        ["@comment.todo"]    = {fg = "#${c.warning}", bold = true},
        ["@comment.warning"] = {fg = "#${c.errorBright}", bold = true},
        ["@comment.note"]    = {fg = "#${a.brightBlue}", bold = true},

        -- Markdown
        ["@markup.heading.1"] = {fg = "#${c.errorBright}", bold = true},
        ["@markup.heading.2"] = {fg = "#${c.warning}", bold = true},
        ["@markup.heading.3"] = {fg = "#${c.success}", bold = true},
        ["@markup.heading.4"] = {fg = "#${a.brightBlue}", bold = true},
        ["@markup.heading.5"] = {fg = "#${a.brightMagenta}", bold = true},
        ["@markup.heading.6"] = {fg = "#${a.brightCyan}", bold = true},
        ["@markup.strong"]    = {fg = "#${c.fg1}", bold = true},
        ["@markup.italic"]    = {fg = "#${c.fg1}", italic = true},
        ["@markup.link"]      = {fg = "#${c.link}", underline = true},
        ["@markup.link.url"]  = {fg = "#${a.brightCyan}"},
        ["@markup.raw"]       = {fg = "#${c.success}"},
        ["@markup.raw.block"] = {fg = "#${c.success}"},

        -- LSP diagnostics
        DiagnosticError = {fg = "#${c.errorBright}"},
        DiagnosticWarn  = {fg = "#${c.warning}"},
        DiagnosticInfo  = {fg = "#${c.info}"},
        DiagnosticHint  = {fg = "#${c.successDim}"},

        -- UI elements
        FloatBorder = {fg = "#${a.brightBlue}"},
        Pmenu       = {bg = "#${c.bg2}", fg = "#${c.fg1}"},
        PmenuSel    = {bg = "#${c.bg3}", fg = "#${c.fg1}"},
      },
      dim_inactive = false,
      transparent_mode = false,
    })

    vim.cmd("colorscheme gruvbox")

    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        vim.api.nvim_set_hl(0, "TelescopeNormal", { bg = "#${c.bg0}" })
        vim.api.nvim_set_hl(0, "TelescopeBorder", { fg = "#${a.brightBlue}" })
        vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#${a.brightBlue}" })
      end,
    })
  '';
}
