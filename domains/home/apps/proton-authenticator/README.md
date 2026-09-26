# proton-authenticator

## Purpose
Installs Proton Authenticator (TOTP app) plus a `proton-authenticator-toggle` wrapper for the shared Hyprland app toggle. It keeps the WebKit/X11 rendering workarounds and shows the app on the current workspace.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-authenticator.enable` → package + toggle wrapper.
- ❌ Does not manage: the SUPER+A keybind (lives in `domains/home/apps/hyprland/parts/behavior.nix`), window rules (same place), or account data/secrets (app-managed).

## Structure
- `index.nix` — options; merges session part outputs and installs the toggle script.
- `parts/session.nix` — package only; services/autostart/env intentionally empty.
- `parts/toggle-script.nix` — rendering environment and call to `hyprland-app-toggle`.

## Changelog
- 2026-09-26: Moved window toggling to the shared Hyprland helper; removed inert autostart option. First launch now appears on the current workspace.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
