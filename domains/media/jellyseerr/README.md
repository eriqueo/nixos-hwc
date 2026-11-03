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
├── index.nix       # Options, upstream security hunks, signed native inputs and image context
├── sys.nix         # Container configuration (mkContainer)
├── README.md       # This file
└── parts/
    ├── config.nix    # Systemd dependencies and private config directory
    ├── settings.nix  # App-owned request flags and preserved settings
    └── setup.nix     # Shared mask, additive user grants and private settings
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

The default preserves Seerr 3.1.0's schema and Node 22.23.4 while backporting
three upstream security fixes. Exact source/result hashes restrict changes to
six compiled files. The fixes sanitize avatar-cache filenames, omit nested user
notification settings, allow only public settings in `/auth/me`, and apply the
upstream media/user/issue filters in movie and TV details.

Build `.#nixosConfigurations.hwc-home.config.system.build.seerrRuntimeImageContext`,
then pass that context to `podman build --network=none --format=docker --pull=never`
with the evaluated `hwc.media.jellyseerr.image` tag. Cache both immutable vendor
inputs first. Keep the qualified old image and current data for recovery.

The 3.5 migration removes `user_settings.discordId`, which breaks 3.1 auth on
recovery. A full compatible migration remains under
[brain-w8phr6](https://refinery.hwc.iheartwoodcraft.com/project/brain-w8phr6).
Remove the backports when a vendor image passes the same security, native and
current-data recovery checks. These three fixes do not clear all app dependencies.

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

- 2026-11-03: Add five fixed-hash, vendor-signed Alpine 3.22 native updates:
  OpenSSL 3.5.9, musl 1.2.5-r13 and zlib 1.3.2-r1. The offline image build
  verifies every archive before installation and restores the node runtime user.

- 2026-11-03: Add exact upstream avatar-cache and user/media privacy backports to
  the same-schema image. Bind the six-file patch manifest and patcher to the image
  identity and production wiring check; fail closed on any source or hunk drift.

- 2026-11-03: Derive request and auto-approval flags from the configured app in a
  bounded, read-only container with no network or config mount. Share that mask
  between future-user defaults and additive existing-user grants. Preserve all
  other user permissions, report SQL failures, and keep config/settings at
  0700/0600. The production-bound settings check covers wiring and invalid masks.

- 2026-10-23: Use the shared pure Node image recipe from `domains/lib/mkContainer.nix`.
  The accepted Seerr recipe bytes, Dockerfile store path and image tag remain
  identical. The runtime wiring check rejects a change to that identity.

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
