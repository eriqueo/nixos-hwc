# domains/paths/

## Purpose

Central path definitions providing machine-aware filesystem abstraction. Enables the same module code to work across laptop (flat PARA structure) and server (tiered storage) without hardcoded paths.

## Boundaries

- **Manages**: Path option definitions (`hwc.paths.*`), machine detection, default path computation
- **Does NOT manage**: Actual directory creation (→ `domains/infrastructure/storage/`), mount points (→ machine hardware configs), file operations

## Structure

```
domains/paths/
└── paths.nix           # Single-file module (Charter Law 10: Primitive Module Exception)
```

## Machine Models

### Laptop (hwc-laptop)
- Flat structure under `~/` using PARA methodology
- Media consolidated at `~/500_media/`
- No tiered storage

### Server (hwc-server)
- Tiered storage: SSD (`/mnt/hot`), HDD (`/mnt/media`)
- Business/AI workloads in `/opt/`
- No PARA folders

## Key Paths

| Path | Laptop | Server |
|------|--------|--------|
| `hwc.paths.media.root` | `~/500_media` | `/mnt/media` |
| `hwc.paths.media.photos` | `~/500_media/510_pictures` | `/mnt/media/photos` |
| `hwc.paths.hot.root` | N/A | `/mnt/hot` |
| `hwc.paths.downloads` | `~/000_inbox/downloads` | `/opt/downloads` |

## Usage

```nix
# In any module
{ config, ... }:
let
  paths = config.hwc.paths;
in {
  # Works on both laptop and server
  services.myapp.dataDir = "${paths.media.root}/myapp";
}
```

## Detection Logic

1. Check `config.hwc.server.enable` flag
2. Fall back to hostname suffix matching (`-laptop`, `-server`)
3. Apply machine-specific defaults
4. Allow per-machine overrides

## Changelog

- 2026-07-11: Added `hwc.paths.removableMedia` (universal default `/mnt`) — mount root for the usb-automount domain (`<removableMedia>/<label>`), part of the Law 3 hardcoded-paths migration.
- 2026-06-11: Added `hwc.paths.recordings` (laptop: `~/500_media/530_videos/recordings`, others: `null`) + `HWC_RECORDINGS_DIR` env export. Screen-recording save location for the new gpu-screen-recorder app. Deliberately under `500_media`, not the Syncthing-shared `000_inbox` (screenshots precedent) — hour-long call videos are too large to replicate to the server.
- 2026-06-02: `hwc.paths.brain.server-replica` default changed from `/mnt/vaults/brain` to `/home/eric/900_vaults/brain`. The vault was physically moved on hwc-server (`/mnt/vaults/brain` no longer exists) so the server replica now lives under the user home, matching the laptop-primary path. Downstream consumers (brain-mcp `vaultPath`, persona-daemon RAG, prometheus alert text) inherit via this option.
- 2026-05-21: Added `hwc.paths.brain.*` namespace (Phase 1 of brain knowledge vault migration). Declares canonical paths for the unified brain vault (laptop-primary, server replica), the mobile capture inbox, vault backups, and the 10 V1–V10 legacy source vaults being merged. Exports matching `HWC_BRAIN_*` env vars. All defaults are conditional (`isLaptop`/`isServer`) so non-matching hosts get `null` and the env vars drop out.
- 2026-02-26: Created README per Law 12
- 2026-02-20: Refactored path detection logic
