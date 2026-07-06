# jellyfin-media-player

## Purpose
Installs the Jellyfin Media Player desktop client, with an optional autostart mode that runs it fullscreen as a systemd user service (TV/kiosk use).

## Boundaries
- ✅ Manages: `hwc.home.apps.jellyfin-media-player.enable` → package install; `autoStart` (default false) → `jellyfin-media-player` user service (`--fullscreen`, restart-on-failure, WantedBy graphical-session.target).
- ❌ Does not manage: the Jellyfin server (see `domains/server/containers/`) or client settings/server credentials (app-managed state).

## Structure
- `index.nix` — options, package install, optional autostart user service.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
