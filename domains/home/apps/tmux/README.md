# tmux

## Purpose
Configures tmux via `programs.tmux`: C-a prefix, vi keys, mouse, 50k history,
vim-style pane navigation/resizing, wl-copy clipboard integration, and a
status bar styled from the HWC theme palette.

## Boundaries
- ✅ `hwc.home.apps.tmux.enable`; full tmux.conf (splits keep cwd, HJKL resize, copy-mode-vi, palette-driven status/borders from `hwc.home.theme.colors`)
- ❌ No plugin manager (TPM) or session persistence
- ❌ Not the workbench multiplexer — that is zellij (`domains/home/apps/zellij/`)

## Structure
- `index.nix` — options + programs.tmux settings and extraConfig

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
