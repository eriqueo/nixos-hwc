# Server Domain

## Scope & Boundary
- Server-lane workloads: containers plus native services for media, AI, automation, networking, and supporting jobs.
- Namespaces follow folder paths (`hwc.server.containers.*`, `hwc.server.native.*`); container defaults come from `_shared` helpers.
- Uses mkContainer (see `domains/server/containers/_shared/`) for OCI hygiene and Charter compliance (PUID/PGID 1000/100).

## Layout
```
domains/server/
├── containers/   # OCI services (mkContainer-based)
│   ├── _shared/    # caddy / directories / network helpers (live)
│   └── arka/       # Arka MCP Gateway (live, imported by machines/server/config.nix)
├── native/
│   └── ai/jobber-mcp/   # Jobber MCP server (only live native service)
├── media/        # Media profile toggle wiring
└── n8n/          # Workflow/profile pieces for n8n
```

## Container Services
The media/arr/torrent stack now lives entirely in `domains/media/` (containers + native splits live there). Server-domain containers retain only the Arka MCP Gateway plus the `_shared/` helpers that other domains import.

## Native Services
- Only `native/ai/jobber-mcp/` remains live, imported directly by `machines/server/config.nix`. The historical aggregator (`native/index.nix`) and all other native subdirs were dead parallel implementations and have been removed.

## Routing & Composition
- Caddy routes live in `domains/networking/routes.nix`; container-specific defaults are in `containers/_shared/caddy.nix`.
- `media/` and `n8n/` provide profile-level toggles that pull together the required container pieces for those stacks.

## Changelog
- 2026-05-21: removed dead `containers/` subdirs (`beets, books, caddy, calibre, gluetun, immich, jellyfin, jellyseerr, lidarr, navidrome, organizr, pihole, pinchflat, prowlarr, qbittorrent, radarr, readarr, recyclarr, sabnzbd, slskd, sonarr, soularr, tdarr`) plus the `containers/index.nix` aggregator. None were imported by any live machine — only `_shared/*` and `arka/` are wired into `machines/server/config.nix`. The media/arr/torrent stack now lives in `domains/media/`. Verified via per-subdir `rg -ln domains/server/containers/<name>/ -t nix` (zero external `.nix` refs) and full eval (drv hashes unchanged).
- 2026-05-21: removed dead `native/` tree (everything except `ai/jobber-mcp/`). Held parallel implementations of services that now live in their respective top-level domains (`domains/data/`, `domains/media/`, `domains/networking/`, `domains/monitoring/`, etc.) plus the dead `native/ai/{ai-bible,local-workflows,mcp,ollama,open-webui}/` subdirs. None were imported by any live `nixosConfiguration` or `homeConfiguration`. Verified via `rg -ln "domains/server/native/<subdir>"` (zero `.nix` imports) and full eval of all four targets (drv hashes unchanged from baseline).
