# Server Domain

## Purpose
- Server-lane workloads: containers plus native services for media, AI, automation, networking, and supporting jobs.

## Boundaries
- Namespaces follow folder paths (`hwc.server.containers.*`, `hwc.server.native.*`); container defaults come from `_shared` helpers.
- Uses mkContainer (see `domains/server/containers/_shared/`) for OCI hygiene and Charter compliance (PUID/PGID 1000/100).

## Structure
```
domains/server/
├── containers/   # OCI services (mkContainer-based)
│   ├── _shared/    # caddy / directories / network helpers (live)
│   └── arka/       # Arka MCP Gateway (live, imported by machines/server/config.nix)
├── native/
│   └── ai/
│       ├── brain-mcp/     # Brain MCP server (Deno) — vault CRUD + semantic search
│       ├── brainvec/      # brainvec semantic-index ingest (vault embeddings via llama-embed)
│       ├── hermes/        # Hermes Agent (Nous Research)
│       ├── home-scout/    # Home Scout MCP + HTTP, plus five timer-driven ingests
│       ├── lead-scout/    # Lead Scout MCP + HTTP, plus isolated Discord approval bot
│       ├── llama-cpp/     # llama.cpp inference (GPU + CPU)
│       ├── market-intelligence/  # Market-intelligence jobs
│       ├── persona-daemon/       # Persona daemon
│       └── research-scout/       # Research Scout MCP + HTTP, plus the arXiv ingest timer
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

- 2026-09-04: `native/ai/lead-scout/` gained an isolated Discord Gateway sidecar for human-approved DataX reply posting. The main service receives the same bot/channel config so it can author interactive review cards, while the sidecar alone consumes button/modal actions; it has boot-time file/secret checks, jittered retries with a five-failures-per-five-minutes ceiling, and a 30-second graceful-stop deadline. Both units pin subsequent Claude calls to Opus. The existing webhook routing remains as fallback, and the bot token stays in the generated agenix mount.
- 2026-08-28: brainvec ingest's checkout refresh now runs GitHub SSH with `-F /dev/null`, bypassing the Home Manager store-owned SSH config that OpenSSH rejects; pull failures remain non-blocking but are logged instead of silently leaving the deployed code stale.
- 2026-08-26: `native/ai/lead-scout/` now declares its own postgres role + database, closing the last gap with home-scout and research-scout. It used to come from `hwc.business.datax` (`domains/business/datax/`), a module whose name stopped describing anything it owned once the database was renamed `datax` → `lead_scout` (85b44464) — a Law 2 break, and the reason that module is now deleted. Carried over: `ensureDatabases`/`ensureUsers` and the `GRANT lead_scout TO eric` peer-auth line. Dropped: the per-database backup registration (`postgresql-db-backup` was retired wholesale the same day in 85b60856, so registering into it would be dead config that reads as a backup; lead_scout is covered by the borg pre-hook's nightly `pg_dumpall` into `/var/lib/backups`), and six raw `GRANT ALL`/`ALTER DEFAULT PRIVILEGES` statements, redundant because the role already owns all 18 tables and every sequence (checked live: the only ACL entries are self-grants and `pg_default_acl` is empty), and the `fb-monitor-bak/schema.sql` apply, which is the stale 2026-05 three-table schema superseded by the app's own `_migrations`. New: `ensureDBOwnership = true`, which moves the database owner `postgres` → `lead_scout`; safe because every object in it is already owned by that role, and it is what supplies CREATE on schema public via `pg_database_owner`.
- 2026-08-15: `native/ai/{lead,home,research}-scout/` — the three long-running `serve` units gained `TimeoutStopSec = "30s"`. Context: every deploy logged `Main process exited, code=exited, status=143/n/a` → `Failed with result 'exit-code'` for each of the three. 143 is 128+15 — node dying to SIGTERM with no handler installed. Measured under the repo's own `tsx` wrapper: no handler → wrapper exits 143; a handler that exits 0 → wrapper exits 0. So this was an app-side omission, and the real fix is app-side (`installGracefulShutdown` in `@scout/server`: close the listener, then crons, then both pg pools, then exit 0, on a 10s deadline). `TimeoutStopSec` only backstops the case where that deadline cannot fire because the event loop is blocked; 30s deliberately leaves the app's own timer room to win, since only the app can close the listener and pools in the right order. **Deliberately NOT `SuccessExitStatus = "143"`** — that would have silenced the symptom and the signal together. With a real handler installed, a 143 from these units now means the handler did not install, which is worth seeing. Found by an adversarial audit of the scout wiring-test harness; app side: scout `eccca5b`+.
- 2026-07-29: `native/ai/research-scout/` — weekly-digest export sinks: new `refineryIntakeUrl` (default loopback `:8060/intake`) and `brainVaultDir` (brainvec's `paths.brain.vault`-with-fallback pattern) options, rendered into the unit env as `REFINERY_INTAKE_URL` / `BRAIN_VAULT_DIR`; `brainVaultDir` added to `ReadWritePaths` so the vault subtree is writable through `ProtectHome = "read-only"` (the app's brain sink writes `_library/research_feed/` notes). Behavior knobs (sink toggles, idea cap) live in the app's `digest_sinks` DB setting, not here — these are host endpoints only. App side: scout a5b3a93.
- 2026-07-29: `native/ai/home-scout/` — the five ingest units (harvest, cadastral, redfin, schools, overlays) gained `wants = [ "network-online.target" ]` to match their existing `after`. `After` without `Wants`/`Requires` is inert ordering: systemd never pulls the target in, so the timers could fire before the network was actually up. The long-running `home-scout.service` already had the pair; only the timer-driven ingests were missing it. Clears five `ordered after 'network-online.target' but doesn't depend on it` eval warnings.
- 2026-07-12: lead-scout gains `channelMap` (profile id → webhook secret name), rendered into the app's `DISCORD_WEBHOOK_FILE_MAP` env — HWC-business classifier profiles (`hwc_bozeman_v1`, `hwc_network_v1`, set in machines/server/config.nix) post to #hwc via the new `discord-webhook-hwc-business` secret while DataX profiles stay on `datax-discord-webhook` (#jt-pros). Context: the bare "N notable posts" Discord messages were the app's stale hardcoded card taxonomy — the tier-driven fix sat uncommitted on hwc-laptop since 2026-06-17 and was committed/deployed to `~/600_apps/lead_scout` today (lead_scout baa1538); cards now carry posts, tags, links, and unanswered flags.
- 2026-07-11: inbox-processor (audio + screenshots) and bloxels-cv — `User = lib.mkForce "eric"` per the native-services Architecture Law (was bare; no-op today, verified by before/after eval).
- 2026-07-11: brainvec `cacheDir` + brain-mcp `brainvecIndex` defaults derive from `hwc.paths.user.home` instead of hardcoded `/home/eric/.cache/brainvec` literals (Law 3 migration, values unchanged).
- 2026-07-10: Added `native/ai/brainvec/` — semantic-index ingest of the brain vault (code in `github.com/eriqueo/brainvec`, cloned to `~/600_apps/brainvec`; oneshot + `*:5/15` timer behind vault-sync; embeds via llama-embed :11502 with nomic task prefixes). brain-mcp gained `search_semantic`/`related_notes` over that index (allow-net +127.0.0.1:11502) — 14 tools total, reachable from laptop `.mcp.json`, tailnet, and claude.ai.
- 2026-07-05: Law 12 burn-down — restructured headings to the required contract (`## Purpose` / `## Boundaries` / `## Structure`); content unchanged, headings renamed/split from the old Scope-&-Boundary/Layout form.
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
