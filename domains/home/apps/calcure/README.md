# calcure

## Purpose
Installs the calcure TUI calendar/task manager with a fully declarative `~/.config/calcure/config.ini` themed to the Nord palette via terminal ANSI color indices (kitty supplies the actual colors). Enable via `hwc.home.apps.calcure.enable`.

## Boundaries
- ✅ `pkgs.calcure`, the config.ini (general/appearance/colors sections), and a desktop entry launching `kitty --title calcure calcure`.
- ❌ No calendar data or sync — event/task backends live elsewhere (Radicale via the mail/calendar stack); does not manage kitty's palette (`domains/home/theme/`).

## Structure
- `index.nix` — enable option, package, desktop entry, generated config.ini with Nord-mapped color slots.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
