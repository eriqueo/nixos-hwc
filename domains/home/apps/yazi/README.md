# yazi

## Purpose
Configures the yazi terminal file manager: core settings, Space-leader
neovim-style keymap (with media-root jumps late-bound from system paths),
palette-driven theme, bundled Lua plugins, and a preview/tooling package set.

## Boundaries
- ✅ `hwc.home.apps.yazi.enable`; `programs.yazi` with shell wrapper `y`, five vendored plugins (full-border, glow, smart-filter, chmod, bookmarks), yazi.toml/keymap.toml/theme.toml/Kanagawa.tmTheme via xdg.configFile
- ✅ Media root derived from `osConfig.hwc.paths.media.root` with `/mnt/media` fallback (Law 3)
- ❌ Not the GUI file manager — see `domains/home/apps/thunar/`
- ❌ Palette definitions live in `domains/home/theme/`

## Structure
- `index.nix` — options, packages, programs.yazi + plugin wiring, config files
- `parts/toml.nix` — yazi.toml (sorting, preview, openers)
- `parts/keymap.nix` — Space-leader keymap, parametrized by mediaRoot
- `parts/appearance.nix` — palette → theme.toml + syntax highlight theme
- `parts/plugins/*.yazi/main.lua` — vendored Lua plugins

## Changelog
- 2026-07-11: keymap.nix dead `? "/mnt/media"` default param dropped — `index.nix` always passes `mediaRoot` (Law 3 audit cleanup, rendered keymap unchanged). The `/mnt/media` standalone-HM fallback in index.nix stays: it is the documented Law 3 escape hatch and not derivable from HM context.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
