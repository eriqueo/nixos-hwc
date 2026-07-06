# proton-mail

## Purpose
Installs the Proton Mail desktop client (`pkgs.protonmail-desktop`), writes a minimal `~/.config/protonmail/desktop/config.json` (minimize-to-tray, notifications), and optionally runs it hidden as a systemd user service on login.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-mail.enable` → package + config file; `autoStart` (default false) → `protonmail` user service (`--hidden`, restart-on-failure, graphical-session.target).
- ❌ Does not manage: account credentials or mailbox data (app-managed), theming (system defaults), or the terminal mail stack (neomutt/aerc modules and the mail domain).

## Structure
- `index.nix` — options; merges session/appearance/behavior part outputs.
- `parts/session.nix` — package + optional autostart user service.
- `parts/behavior.nix` — writes the desktop config.json.
- `parts/appearance.nix` — intentionally empty (system theming; no files).

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
