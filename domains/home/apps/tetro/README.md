# tetro

## Purpose
Installs tetro, a third-party terminal tetromino game (Strophox/tetro-tui)
consumed as the `tetro` flake input's prebuilt package, and publishes a
launcher entry that hosts the TUI in kitty.

## Boundaries
- ✅ Installs `inputs.tetro.packages.<system>.default` when `hwc.home.apps.tetro.enable = true`
- ✅ `xdg.desktopEntries.tetro` — wofi/rofi drun entry running `kitty --class tetro-tui -e tetro-tui`
- ❌ No theme/keymap configuration — the upstream app exposes no such surface yet
- ❌ Not built here — the flake input ships the binary

## Structure
- `index.nix` — options, flake-input package install, desktop entry

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
