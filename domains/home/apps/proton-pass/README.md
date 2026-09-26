# proton-pass

## Purpose
Installs the Proton Pass desktop client. Waybar uses Hyprland's shared app toggle to show it on the current workspace.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-pass.enable` → desktop package.
- ❌ Does not manage: the app's own runtime config at `~/.config/Proton Pass/` (app needs write access; theme set manually in-app), vault data/credentials, browser extensions, or window rules (in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — enable option and package wiring.
- `parts/session.nix` — desktop package.

## Changelog
- 2026-09-26: Removed the unused `~/.config/protonpass/config.json` producer and inert options. Proton Pass keeps its real writable config; the Waybar button uses the Hyprland toggle.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
