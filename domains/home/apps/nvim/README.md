# Neovim Domain

Full IDE-like Neovim configuration with lazy.nvim plugin management.

## Purpose

Provides a complete Neovim setup with:
- Telescope fuzzy finding
- Treesitter syntax highlighting
- LSP integration
- Autocompletion (nvim-cmp)
- Harpoon quick navigation
- Oil file explorer
- Custom keymaps with space as leader

## Boundaries

- **Owns**: All Neovim configuration, plugins, and keymaps
- **Does NOT own**: Editor selection logic (handled by development domain)

## Structure

```
nvim/
├── index.nix           # Main aggregator, deploys lua via xdg.configFile
├── README.md           # This file
└── parts/
    └── lua/
        ├── core/
        │   ├── init.lua        # Entry point, requires all modules
        │   ├── keymaps.lua     # All keybindings (leader=space)
        │   ├── options.lua     # Vim options
        │   ├── plugins.lua     # lazy.nvim plugin definitions
        │   └── colorscheme.lua # Gruvbox with Deep Nord colors
        └── plugins/
            ├── telescope.lua   # Fuzzy finder config
            ├── treesitter.lua  # Syntax highlighting
            ├── lsp.lua         # Language server config
            └── cmp.lua         # Autocompletion config
```

## Key Bindings

| Keybind | Description |
|---------|-------------|
| `<leader>ff` | Find files in current directory |
| `<leader>fn` | Find files in ~/.nixos |
| `<leader>fg` | Live grep |
| `<leader>fb` | Find buffers |
| `<leader>ov` | Open Oil file explorer |
| `<leader>1-4` | Harpoon quick files |
| `gd` | Go to definition |
| `K` | Hover documentation |

## Changelog

- 2026-03-12: Initial domain creation, migrated from ~/.config/nvim
- 2026-06-02: Migrate `nvim-treesitter-textobjects` block to the new `main`-branch API (`require("nvim-treesitter-textobjects").setup` + explicit keymaps). Fixes "module 'nvim-treesitter.configs' not found" startup error caused by the v1.0 rewrite removing the legacy entry point.
