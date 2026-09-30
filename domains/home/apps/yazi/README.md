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
- `parts/plugins/bookmarks.yazi/store.py` — atomic, locked favorites storage
- `parts/plugins/bookmarks.yazi/test.py` — storage contracts and real-terminal acceptance

## Navigation

Favorites always occupy the left column. `Alt+j/k` opens the next/previous
favorite. `Alt+h` focuses that column; `j/k` selects and Enter opens.
`Alt+l` or Escape returns focus to files. In favorites, `a/r/d` adds the
current folder, renames a favorite, or removes a favorite after confirmation.
`Space b a` adds from the file pane. Removal leaves the folder intact.

`Z` finds files with FZF; `z` finds visited folders with Zoxide.
Preview scrolling uses `Alt+Shift+j/k`. `h` still opens the parent folder.

User favorites live in `$XDG_DATA_HOME/yazi/favorites.json` (normally
`~/.local/share/yazi/favorites.json`). This is CRITICAL user data; retain it
with home backups. Defaults seed only an absent file. Saves lock, replace
atomically, and refuse corrupt input or more than 128 entries/64 KiB.
Unavailable destinations warn instead of opening another folder.
The bookmarks package runs storage tests when built. Terminal acceptance
runs `test.py --config-json FILE` against evaluated Home Manager configuration.

## Changelog
- 2026-09-30: Replace the parent column with persistent favorites and synchronous focus routing; add editable bookmarks, natural sorting, Zoxide history, and terminal acceptance checks.
- 2026-07-11: keymap.nix dead `? "/mnt/media"` default param dropped — `index.nix` always passes `mediaRoot` (Law 3 audit cleanup, rendered keymap unchanged). The `/mnt/media` standalone-HM fallback in index.nix stays: it is the documented Law 3 escape hatch and not derivable from HM context.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
