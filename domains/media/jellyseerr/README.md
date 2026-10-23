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
├── index.nix       # Options, runtime image recipe and module aggregator
├── sys.nix         # Container configuration (mkContainer)
├── README.md       # This file
└── parts/
    ├── config.nix    # Systemd dependencies and tmpfiles
    ├── settings.nix  # Declarative values and app-state preservation
    └── setup.nix     # Pre-start setup scripts
```

## Configuration

### Module Options

```nix
hwc.media.jellyseerr = {
  enable = true;                                    # Enable Seerr
  # image defaults to the qualified local runtime tag derived from its recipe.
  network.mode = "media";                           # Network mode: "media" or "vpn"
  gpu.enable = false;                               # GPU acceleration (not needed)
};
```

### Runtime image

The temporary default retains exact Seerr 3.1.0 and its schema while copying only
Node 22.23.4 from a pinned official Seerr image. Both inputs use immutable digests.
Build `.#nixosConfigurations.hwc-home.config.system.build.seerrRuntimeImageRecipe`,
then use its Dockerfile with `podman build --format=docker --pull=never` and the
evaluated `hwc.media.jellyseerr.image` tag. Cache both
pinned inputs first. This build does not restart the service. Keep the old image
and current data for recovery; never restore stale data over later requests.

The 3.5 migration removes `user_settings.discordId`, which breaks 3.1 auth on
rollback. Broader application advisories and compatible migration remain tracked
as `brain-w8phr6`; the Node-only image is not a fully patched application claim.
Remove the custom image after an upstream release passes data/recovery checks.

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

- Recovery candidate: pin the exact prior image while keeping atomic settings
  preservation and current data. This is an availability fallback with the old
  Node runtime; it does not restore a stale database.

- 2026-10-23: Add an immutable runtime-only image recipe and derived local tag.
  It replaces Node while retaining exact app bytes and database compatibility;
  application upgrade/recovery remains separately tracked.

- 2026-10-23: Reconcile declared settings atomically while retaining app identity,
  API/VAPID keys, library selection and unknown fields on matching server IDs.
  Nix still owns its declared policy, secrets and server membership. Invalid
  JSON or missing keys leave existing settings intact. The production-bound
  `seerr-settings-preservation` check covers preservation, rotation, idempotence,
  failure containment and first-start setup.

- 2026-06-09: Access moved from tailnet port `:5543` to name-based vhost `jellyseerr.hwc.iheartwoodcraft.com` (shared `*.hwc.iheartwoodcraft.com` wildcard cert). `applicationUrl` in settings updated to match. See `domains/networking/README.md`.
- 2026-03-07: Upgraded from Jellyseerr to Seerr (ghcr.io/seerr-team/seerr:latest), added --init flag
- 2026-03-07: Fixed Radarr/Sonarr connectivity by using container hostnames instead of gateway IP
