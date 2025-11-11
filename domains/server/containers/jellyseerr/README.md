# Jellyseerr Container Module

## Overview

Jellyseerr is a request management and media discovery tool for Jellyfin. It provides a clean interface for users to request movies and TV shows, which are then automatically sent to Sonarr and Radarr for download.

## Features

- Media discovery with rich metadata from TMDB
- User request management and approval workflows
- Direct integration with Jellyfin, Sonarr, and Radarr
- Multi-user support with customizable permissions
- Email and webhook notifications
- Request tracking and status updates

## Configuration

### Module Options

```nix
hwc.services.containers.jellyseerr = {
  enable = true;                                      # Enable Jellyseerr
  image = "lscr.io/linuxserver/jellyseerr:latest";   # Container image
  network.mode = "media";                             # Network mode: "media" or "vpn"
  gpu.enable = false;                                 # GPU acceleration (not needed)
};
```

### Network Configuration

- **Default Port**: 5055
- **Network Mode**: `media` (connects to other services)
- **Reverse Proxy**: Available via `/jellyseerr` (subpath) or dedicated port `:5543`

### Dependencies

Jellyseerr depends on:
- **Jellyfin** - Media server for content availability
- **Sonarr** - TV show management and downloading
- **Radarr** - Movie management and downloading

### Volume Mounts

- `/opt/downloads/jellyseerr:/config` - Configuration and database

## Initial Setup

1. **Enable the service** in your profile:
   ```nix
   hwc.services.containers.jellyseerr.enable = true;
   ```

2. **Rebuild NixOS**:
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-server
   ```

3. **Access Jellyseerr**:
   - Via Caddy subpath: `https://hwc.ocelot-wahoo.ts.net/jellyseerr`
   - Via Caddy port: `https://hwc.ocelot-wahoo.ts.net:5543/`
   - Direct container port (local): `http://localhost:5055`

4. **Complete setup wizard**:
   - Sign in with your Jellyfin account
   - Configure Jellyfin server connection
   - Add Sonarr and Radarr instances
   - Configure user permissions and quotas

## Integration Guide

### Jellyfin Connection

- **Server URL**: `http://jellyfin:8096` (via container network)
- **API Key**: Generate in Jellyfin Dashboard → API Keys

### Sonarr Connection

- **Server URL**: `http://sonarr:8989` (via container network)
- **API Key**: Found in Sonarr Settings → General
- **Root Folder**: `/tv` or `/movies` as configured
- **Quality Profile**: Set default quality profile for requests

### Radarr Connection

- **Server URL**: `http://radarr:7878` (via container network)
- **API Key**: Found in Radarr Settings → General
- **Root Folder**: `/movies` as configured
- **Quality Profile**: Set default quality profile for requests

## Architecture Compliance

### HWC Charter Compliance

- **Domain**: `domains/server/containers/jellyseerr/`
- **Namespace**: `hwc.services.containers.jellyseerr.*`
- **Options**: Defined in `options.nix` only
- **Implementation**: Uses shared container helpers from `_shared/pure.nix`
- **Network**: Integrated with media-network via shared infrastructure

### Module Structure

```
jellyseerr/
├── index.nix           # Module aggregator
├── options.nix         # Option definitions
├── sys.nix            # Container configuration
└── parts/
    ├── config.nix     # Systemd and reverse proxy config
    ├── scripts.nix    # Helper scripts (placeholder)
    ├── pkgs.nix       # Package definitions (placeholder)
    └── lib.nix        # Library functions (placeholder)
```

## Troubleshooting

### Container fails to start
- Check dependencies are running: `podman ps | grep -E "jellyfin|sonarr|radarr"`
- Check network exists: `podman network ls | grep media-network`
- Check logs: `journalctl -u podman-jellyseerr -f`

### Cannot connect to Jellyfin/Sonarr/Radarr
- Verify container network mode is `media`
- Use container names as hostnames (e.g., `http://jellyfin:8096`)
- Ensure all services are on the same container network

### Requests not being sent to Sonarr/Radarr
- Verify API keys are correct
- Check root folders exist in the containers
- Review quality profiles are configured
- Check Jellyseerr logs for API errors

## References

- [Jellyseerr Documentation](https://docs.jellyseerr.dev/)
- [LinuxServer.io Jellyseerr Image](https://docs.linuxserver.io/images/docker-jellyseerr)
- [HWC Charter](../../../charter.md)
