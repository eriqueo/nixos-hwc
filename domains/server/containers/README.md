# Server Containers

## Purpose
OCI container workloads via Podman using helper functions for Law 5 compliance.

## Boundaries
- Manages: Container definitions, volumes, networking, health checks
- Does NOT manage: Native services → `native/`, container runtime → `system/virtualization/`

## Structure
```
containers/
├── _shared/           # Container helpers (Law 5)
│   ├── pure.nix       # mkContainer - application containers
│   ├── infra.nix      # mkInfraContainer - infrastructure containers
│   └── ...            # Network, routes, directories
├── audiobookshelf/    # Audiobook server
├── caddy/             # Reverse proxy
├── gluetun/           # VPN gateway (uses mkInfraContainer)
├── immich/            # Photo management
├── jellyfin/          # Media server
├── jellyseerr/        # Request management
├── pihole/            # DNS filtering (uses mkInfraContainer)
├── *arr/              # Media automation stack
├── paperless/         # Document management
└── ... (25+ containers)
```

## Usage

All containers MUST use the helpers from `_shared/`:
- **mkContainer** (`pure.nix`): For standard app containers
- **mkInfraContainer** (`infra.nix`): For infrastructure containers with special requirements

See `_shared/README.md` for detailed API documentation.

## Changelog
- 2026-02-28: Law 5 compliance - all containers migrated to use helpers
- 2026-02-28: Added mkInfraContainer for gluetun, pihole
- 2026-02-28: Updated mkContainer with nvidia-cdi GPU support
- 2026-02-28: Added README for Charter Law 12 compliance
