# qbittorrent

## Purpose
Installs the qBittorrent desktop torrent client. A one-package module generated
via `domains/lib/mkSimpleApp.nix` — no configuration is managed here.

## Boundaries
- ✅ Installs `pkgs.qbittorrent` when `hwc.home.apps.qbittorrent.enable = true`
- ❌ No app settings, theming, or download paths — qBittorrent manages its own config at runtime
- ❌ Not the server-side torrent stack — that lives under `domains/server/containers/`

## Structure
- `index.nix` — mkSimpleApp call declaring name, description, and package

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
