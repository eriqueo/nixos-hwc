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
├── options.nix         # hwc.home.apps.nvim.enable
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
