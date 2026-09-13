# proton-mail

## Purpose
Installs the Proton Mail desktop client (`pkgs.protonmail-desktop`), writes a minimal `~/.config/protonmail/desktop/config.json` (minimize-to-tray, notifications), and optionally runs it hidden as a systemd user service on login.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-mail.enable` → package, integrated-GPU desktop entry, and config file; `autoStart` (default false) → `protonmail` user service (`--hidden`, restart-on-failure, graphical-session.target).
- ❌ Does not manage: account credentials or mailbox data (app-managed), theming (system defaults), or the terminal mail stack (neomutt/aerc modules and the mail domain).

## Structure
- `index.nix` — options; merges session/appearance/behavior part outputs.
- `parts/session.nix` — package, integrated-GPU desktop entry, and optional autostart user service.
- `parts/behavior.nix` — writes the desktop config.json.
- `parts/appearance.nix` — intentionally empty (system theming; no files).

## Changelog
- 2026-09-13: Route the normal `proton-mail.desktop` launch through the same boundary as autostart, and correct the wrapper target to the package's real `proton-mail` executable. Live attribution showed the app runs as a desktop-launched transient scope because autostart is disabled.
- 2026-09-12: Start the autostart client through the system-owned `gpu-integrated` boundary when available, keeping Electron's device probing from holding the laptop dGPU open.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
