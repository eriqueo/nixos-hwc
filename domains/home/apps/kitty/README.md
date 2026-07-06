# kitty

## Purpose
Configures the Kitty terminal emulator via `programs.kitty`: font (from `hwc.home.theme.fonts.mono`), window/transparency/scrollback/tab settings, clipboard keybinds, mouse maps tuned for grabbed TUI apps (aerc), zsh shell integration, and palette-driven colors.

## Boundaries
- ✅ Manages: `hwc.home.apps.kitty.enable` → full kitty settings, keybindings, raw `extraConfig` mouse maps, appearance derived from the theme palette.
- ❌ Does not manage: the palette itself (`domains/home/theme`), the shell (`domains/home/core/shell`), or which apps launch kitty (hyprland keybinds live in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — options + `programs.kitty` settings, keybindings, extraConfig, shell integration.
- `parts/appearance.nix` — pure function: theme palette colors → kitty color settings (fg/bg/cursor/selection/url + ANSI 0-15), with fallbacks.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
