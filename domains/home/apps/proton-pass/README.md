# proton-pass

## Purpose
Installs the Proton Pass password manager desktop client and writes `~/.config/protonpass/config.json` with tray/notification/auto-lock (15 min) behavior and a browser-integration flag.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-pass.enable` → package + config.json; `browserIntegration` option (default true) fed into that config; an `autoStart` option exists but is currently inert (session part returns no services — startup is handled via Hyprland exec-once conventions).
- ❌ Does not manage: the app's own runtime config at `~/.config/Proton Pass/` (app needs write access; theme set manually in-app), vault data/credentials, browser extensions, or window rules (in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — options (`enable`, `autoStart`, `browserIntegration`); merges part outputs.
- `parts/session.nix` — package only; services intentionally empty.
- `parts/behavior.nix` — writes `.config/protonpass/config.json`.
- `parts/appearance.nix` — intentionally empty (documents why HM can't own the app's real config).

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
