# proton-authenticator

## Purpose
Installs Proton Authenticator (TOTP app) plus a `proton-authenticator-toggle` script for Hyprland: launches the app with Wayland rendering workarounds (`WEBKIT_DISABLE_DMABUF_RENDERER=1`, `GDK_BACKEND=x11`) or toggles the existing window between the current workspace and the workspace-8 scratchpad.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-authenticator.enable` → package + toggle script; an `autoStart` option exists but is currently inert (session part returns no services/autostart files — startup is handled by Hyprland exec-once conventions).
- ❌ Does not manage: the SUPER+A keybind (lives in `domains/home/apps/hyprland/parts/behavior.nix`), window rules (same place), or account data/secrets (app-managed).

## Structure
- `index.nix` — options; merges session part outputs and installs the toggle script.
- `parts/session.nix` — package only; services/autostart/env intentionally empty.
- `parts/toggle-script.nix` — `proton-authenticator-toggle` shell script (hyprctl + jq launch/show/hide logic).

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
