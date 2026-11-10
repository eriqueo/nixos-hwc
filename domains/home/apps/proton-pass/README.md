# proton-pass

## Purpose
Installs the Proton Pass desktop client. Its native colored tray icon opens the app from Waybar.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-pass.enable` → desktop package with Linux tray activation wired to its existing open handler.
- ❌ Does not manage: the app's own runtime config at `~/.config/Proton Pass/` (app needs write access; theme set manually in-app), vault data/credentials, browser extensions, or window rules (in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — enable option, package and exact-match Linux tray patch.

## Changelog
- 2026-11-09: Inline the package-only session wrapper; preserve the exact Linux tray click patch.
- 2026-09-26: Wired Linux tray activation to Proton Pass's existing open handler. The upstream bundle only registered a Windows double-click handler, so Waybar's left-click activation did nothing.
- 2026-09-26: Removed the unused `~/.config/protonpass/config.json` producer and inert options. Proton Pass keeps its real writable config.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
