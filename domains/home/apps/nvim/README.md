# Neovim Domain

Full IDE-like Neovim configuration with lazy.nvim plugin management.

## Purpose

Provides a complete Neovim setup with:
- fzf-lua fuzzy finding (primary; native fzf binary, fast over huge trees)
- Telescope (secondary pickers: help/commands/keymaps/resume)
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
            ├── fzf-lua.lua     # Primary fuzzy finder (native fzf binary)
            ├── telescope.lua   # Secondary pickers (help/commands/keymaps)
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
- 2026-06-09: Added `IogaMaster/tuxedo.nvim` — floating todo.txt popup, companion to the tuxedo CLI (`hwc.home.apps.tuxedo`). Lazy-loaded on `:Tuxedo` / `<leader>td`.
- 2026-07-06: which-key.nvim configured for the HWC standard popup look (was a bare `setup()`): modern preset, double-line border, `key → desc` rows via `icons.separator`, no per-mapping icons. `parts/appearance.nix` themes the `WhichKey*` highlight groups from the palette (raised bg3 card, copper border, inverted cream title chip, copper keys, cool-accent groups) so the default red group colour is gone — mirrors the aerc which-key card.
- 2026-06-24: Added `ibhagwan/fzf-lua` as the primary fuzzy finder and repointed the file/content/buffer keymaps (`ff`/`fg`/`fb`/`fr`/`fn`/`fs`) at it. Telescope's Lua-side result pipeline crawls and mis-filters past ~40k entries even with `fzf-native`; fzf-lua offloads filtering to the native `fzf` binary and stays instant on large trees (e.g. content vaults). Telescope retained for help/commands/keymaps/resume pickers. New file `parts/lua/plugins/fzf-lua.lua` deployed via `xdg.configFile`.
