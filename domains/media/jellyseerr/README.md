# Seerr Container Module

## Purpose

Seerr (formerly Jellyseerr) is a request management and media discovery tool for Jellyfin. It provides a clean interface for users to request movies and TV shows, which are then automatically sent to Sonarr and Radarr for download.

## Boundaries

- Manages the Seerr container and its configuration
- Integrates with Jellyfin, Sonarr, and Radarr
- Does NOT manage the underlying media services

## Structure

```
jellyseerr/
├── index.nix       # Options and module aggregator
├── sys.nix         # Container configuration (mkContainer)
├── README.md       # This file
└── parts/
    ├── config.nix    # Systemd dependencies and tmpfiles
    ├── settings.nix  # Declarative settings.json generation
    └── setup.nix     # Pre-start setup scripts
```

## Configuration

### Module Options

```nix
hwc.media.jellyseerr = {
  enable = true;                                    # Enable Seerr
  image = "ghcr.io/seerr-team/seerr:latest";       # Container image
  network.mode = "media";                           # Network mode: "media" or "vpn"
  gpu.enable = false;                               # GPU acceleration (not needed)
};
```

### Network Configuration

- **Default Port**: 5055
- **Network Mode**: `media` (connects to other services)
- **Reverse Proxy**: Available via `/jellyseerr` subpath

### Dependencies

Seerr depends on:
- **Jellyfin** - Media server for content availability
- **Sonarr** - TV show management
- **Radarr** - Movie management

### Volume Mounts

- `/opt/apps/jellyseerr/config:/app/config` - Configuration and database

## Changelog

- 2026-03-07: Upgraded from Jellyseerr to Seerr (ghcr.io/seerr-team/seerr:latest), added --init flag
- 2026-03-07: Fixed Radarr/Sonarr connectivity by using container hostnames instead of gateway IP
