# calcurse

## Purpose
Installs the calcurse TUI calendar/scheduler with a declarative XDG config (`~/.config/calcurse/conf`): monthly view, Monday week start, notify bar, "blue on default" theme riding the terminal's Nord palette. Enable via `hwc.home.apps.calcurse.enable`.

## Boundaries
- ✅ `pkgs.calcurse`, the generated `calcurse/conf`, and a desktop entry launching it in kitty.
- ❌ No appointment/todo data and no CalDAV sync (task/calendar backends live in the mail/calendar stack); terminal colors come from the kitty theme, not this module.

## Structure
- `index.nix` — enable option, package, desktop entry, generated conf.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
