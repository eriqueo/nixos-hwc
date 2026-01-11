# Server Domain

## Scope & Boundary
- Server-lane workloads: containers plus native services for media, AI, automation, networking, and supporting jobs.
- Namespaces follow folder paths (`hwc.server.containers.*`, `hwc.server.native.*`); container defaults come from `_shared` helpers.
- Uses mkContainer (see `domains/server/containers/_shared/`) for OCI hygiene and Charter compliance (PUID/PGID 1000/100).

## Layout
```
domains/server/
├── containers/   # OCI services (mkContainer-based)
│   ├── _shared/
│   ├── beets/ beets/parts
│   ├── books/ books/parts
│   ├── caddy/ caddy/parts
│   ├── gluetun/ gluetun/parts
│   ├── immich/ immich/parts
│   ├── jellyfin/ jellyfin/parts
│   ├── jellyseerr/ jellyseerr/parts
│   ├── lidarr/ lidarr/parts
│   ├── navidrome/ navidrome/parts
│   ├── organizr/ organizr/parts
│   ├── pihole/
│   ├── prowlarr/ prowlarr/parts
│   ├── qbittorrent/ qbittorrent/parts
│   ├── radarr/ radarr/parts
│   ├── recyclarr/ recyclarr/parts
│   ├── sabnzbd/ sabnzbd/parts
│   ├── slskd/ slskd/parts
│   ├── sonarr/ sonarr/parts
│   ├── soularr/ soularr/parts
│   └── tdarr/ tdarr/parts
├── native/       # Native service stack (aggregates all subdomains below)
│   ├── ai/
│   ├── backup/
│   ├── beets-native/
│   ├── business/
│   ├── couchdb/
│   ├── downloaders/
│   ├── fabric-api/
│   ├── frigate/
│   ├── immich/
│   ├── jellyfin/
│   ├── media/
│   ├── monitoring/
│   ├── n8n/
│   ├── navidrome/
│   ├── networking/
│   ├── orchestration/
│   └── storage/
├── media/        # Media profile toggle wiring
├── n8n/          # Workflow/profile pieces for n8n
└── routes.nix    # HTTP routing map for container + native services
```

## Container Services (complete list)
Enabled via `hwc.server.containers.<name>.enable`:
- beets, books, caddy, gluetun, immich, jellyfin, jellyseerr, lidarr, navidrome
- organizr, pihole, prowlarr, qbittorrent, radarr, recyclarr, sabnzbd
- slskd, sonarr, soularr, tdarr

## Native Services & Nesting
- `native/` is the single aggregator imported by `domains/server/index.nix`; each subdirectory exposes `hwc.server.native.<service>.*` options.
- Categories: AI (ollama/open-webui/MCP), backup jobs, beets-native, business APIs, CouchDB, downloader orchestration, Frigate, Immich, Jellyfin, media glue, monitoring stack (Prometheus/Grafana/exporters), n8n workflows, Navidrome, networking helpers, orchestration utilities, and storage management.

## Container vs Native Duplication
- Some services exist in both lanes (e.g., Immich, Jellyfin, Beets, downloader stack) to support host-by-host choices and migrations.
- Pick one lane per service per host; options mirror the service name in the respective namespace (`hwc.server.containers.*` vs `hwc.server.native.*`).
- Shared policy: mkContainer for OCI, `config.hwc.paths.*` for mounts, and the unified PUID=1000/PGID=100 permission model.

## Routing & Composition
- `routes.nix` defines Caddy routing for both container and native services; container-specific defaults live under `containers/_shared/caddy.nix`.
- `media/` and `n8n/` provide profile-level toggles that pull together the required container/native pieces for those stacks.
