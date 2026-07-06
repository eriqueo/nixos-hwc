# qutebrowser

## Purpose
Installs qutebrowser and generates its full `config.py`: behavior defaults
(kitty+nvim editor, adblock `both`, autoplay off, downloads to ~/Downloads),
palette-driven colors, and Space-leader vim-style keybindings.

## Boundaries
- ✅ `hwc.home.apps.qutebrowser.enable`; `package` / `extraPackages` overrides; writes `~/.config/qutebrowser/config.py` (autoconfig disabled)
- ✅ Theme colors derived from `hwc.home.theme.colors` with guarded fallbacks
- ❌ No per-site settings, greasemonkey scripts, or session state — runtime `:set` changes are session-only by design
- ❌ Not the default-browser wiring (xdg.mimeApps lives elsewhere)

## Structure
- `index.nix` — options, config.py assembly, package install, assertion
- `parts/appearance.nix` — pure function: palette tokens → qutebrowser color settings
- `parts/keybindings.nix` — Space-leader keybinding grammar (matches yazi/todui)

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
