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
│   └── ai/
│       ├── brain-mcp/     # Brain MCP server (Deno)
│       ├── hermes/        # Hermes Agent (Nous Research)
│       ├── jobber-mcp/    # Jobber MCP server
│       ├── lead-scout/    # Lead Scout MCP + HTTP
│       └── llama-cpp/     # llama.cpp inference (GPU + CPU)
├── services/
│   ├── bloxels-cv/       # Bloxels grid photo classifier (path watcher on inbox-mobile)
│   ├── inbox-processor/  # Phone capture processor (Whisper + Tesseract)
│   └── radicale/         # Self-hosted CalDAV (tasks.hwc.*, two-way task sync)
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
- 2026-07-03: Added `services/bloxels-cv/` — `hwc.server.services.bloxelsCv`, a
  systemd path watcher on `inbox-mobile/bloxels` (phone Syncthing share). Each
  dropped photo of the printed 13×13 Bloxels grid runs `bloxels-capture` (from
  the private `bloxels-cv` flake input; ArUco detect → perspective rectify →
  CIELAB nearest-color classify) and writes `results/<photo>/{grid.json,debug.png,log.txt}`
  back into the share; photos archive to `done/<date>/` or `failed/<date>/`.
  Same input/oneshot anatomy as `inbox-processor`.
- 2026-06-19: Added `deploy/` — `hwc.server.deploy` provides an interactive `deploy`
  CLI (on PATH, server only). Auto-discovers app repos under `appsDir` (default
  `~/600_apps`) that carry an executable `deploy.sh`, presents an `fzf` picker (or
  `deploy <app>` direct), and execs that app's recipe. Recipes live WITH each app
  (late binding — new deployable app = drop a `deploy.sh`, no Nix edit); the
  dispatcher only discovers/picks/execs and supplies the toolchain PATH
  (node/git/sudo/podman-compose) via `runtimeInputs`. Recipes added to
  datax-monitor (tsx + ui build + restart), lead_scout (tsx + frontend build +
  restart; supersedes the inline `lead-scout-deploy`), sr_analyzer (podman-compose
  rebuild). Each recipe pulls only if the tree is clean + has an upstream, else
  deploys in place — safe on the currently-dirty server checkouts.
- 2026-06-11: Added `services/radicale/` — self-hosted CalDAV server
  (localhost:5232, Caddy vhost `tasks`) for two-way task sync with list
  creation (companion to `domains/mail/tasks` radicale pair + todui `N`).
  htpasswd auth from the `radicale-htpasswd` agenix secret. Enabled in
  machines/server/config.nix; see its README for the deploy runbook.
- 2026-06-09: Law 3 finish — brain-mcp (server.ts path + vaultPath default), lead-scout (projectDir), jobber-mcp (projectDir/envFile) now derive from `hwc.paths` with value-preserving fallbacks. Server drv hash unchanged.
- 2026-06-09: Removed `native/.immich-native-reference/` (4,100-line unimported reference module; live Immich is the container in `domains/media/`). Recoverable from git history.
- 2026-06-09: Law 10 migration — inlined `options.nix` into `index.nix` for all 7 `native/ai/*` modules and `services/inbox-processor`. Pure relocation; server toplevel drv hash unchanged.
- 2026-06-09: Removed stale `_shared/` legacy files: `caddy.nix` (dormant `hwc.server.reverseProxy` — superseded by `domains/networking/reverseProxy.nix`, which is the live Caddy), `network.nix` (byte-identical duplicate of `domains/networking/podman-network.nix`; both were imported, silently doubling the init-media-network script), and orphans `lib.nix`, `pure.nix`, `arr-config.nix` (superseded by `domains/lib/`; only referenced by dead `routes-lib.nix`). `directories.nix` remains the only live `_shared` file. Verified by full eval.
- 2026-05-29: Added `native/ai/llama-cpp/` — native systemd llama.cpp inference. Two services share one CUDA-built binary: GPU service (LFM2-2.6B Q4 on Quadro P1000, port 26443→11500) and CPU service (LFM2-24B-A2B Q4 in RAM, port 27443→11501). Models auto-fetched to `${hwc.paths.ai.models}/llama-cpp/`.
- 2026-05-21: removed dead `containers/` subdirs (`beets, books, caddy, calibre, gluetun, immich, jellyfin, jellyseerr, lidarr, navidrome, organizr, pihole, pinchflat, prowlarr, qbittorrent, radarr, readarr, recyclarr, sabnzbd, slskd, sonarr, soularr, tdarr`) plus the `containers/index.nix` aggregator. None were imported by any live machine — only `_shared/*` and `arka/` are wired into `machines/server/config.nix`. The media/arr/torrent stack now lives in `domains/media/`. Verified via per-subdir `rg -ln domains/server/containers/<name>/ -t nix` (zero external `.nix` refs) and full eval (drv hashes unchanged).
- 2026-05-21: removed dead `native/` tree (everything except `ai/jobber-mcp/`). Held parallel implementations of services that now live in their respective top-level domains (`domains/data/`, `domains/media/`, `domains/networking/`, `domains/monitoring/`, etc.) plus the dead `native/ai/{ai-bible,local-workflows,mcp,ollama,open-webui}/` subdirs. None were imported by any live `nixosConfiguration` or `homeConfiguration`. Verified via `rg -ln "domains/server/native/<subdir>"` (zero `.nix` imports) and full eval of all four targets (drv hashes unchanged from baseline).
