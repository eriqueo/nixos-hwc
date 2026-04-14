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

- 2026-02-26: Created README per Law 12
- 2026-02-20: Refactored path detection logic
