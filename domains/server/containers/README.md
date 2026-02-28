# Server Containers

## Purpose
OCI container workloads via Podman using mkContainer helper.

## Boundaries
- Manages: Container definitions, volumes, networking, health checks
- Does NOT manage: Native services → `native/`, container runtime → `system/virtualization/`

## Structure
```
containers/
├── _shared/           # mkContainer helper (Law 5)
├── audiobookshelf/    # Audiobook server
├── caddy/             # Reverse proxy
├── immich/            # Photo management
├── jellyfin/          # Media server
├── jellyseerr/        # Request management
├── *arr/              # Media automation stack
├── paperless/         # Document management
├── pihole/            # DNS filtering
└── ... (25+ containers)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
