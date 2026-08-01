# domains/media/ — Media Domain

## Purpose

The largest domain — encompasses all media streaming, acquisition, processing,
photo management, and video surveillance services.

## Boundaries

- Owns: all media containers and native services
- Does NOT own: networking/reverse proxy (that's `domains/networking/`), monitoring exporters (those register scrape configs via monitoring domain)

## Structure

```
media/
├── index.nix                # Domain aggregator
├── README.md                # This file
│
├── jellyfin-container/      # Jellyfin media server (container)
├── jellyfin-native/         # Jellyfin media server (native NixOS)
├── navidrome-container/     # Navidrome music server (container)
├── navidrome-native/        # Navidrome music server (native NixOS)
├── audiobookshelf/          # Audiobook/podcast server
├── jellyseerr/              # Media request management
│
├── sonarr/                  # TV show management
├── radarr/                  # Movie management
├── lidarr/                  # Music management
├── prowlarr/                # Indexer management
├── readarr/                 # Book management
├── qbittorrent/             # BitTorrent client
├── sabnzbd/                 # Usenet client
│
├── tdarr/                   # Video transcoding
├── organizr/                # Service dashboard
├── mousehole/               # MAM IP updater
├── pinchflat/               # YouTube subscription manager
├── beets-container/         # Music organizer (container)
├── beets-native/            # Music organizer (native)
├── recyclarr/               # *arr quality profile sync
├── slskd/                   # Soulseek client
├── soularr/                 # Soulseek-Lidarr integration
├── calibre/                 # Ebook management
├── books/                   # LazyLibrarian
│
├── immich-container/        # Photo management (container)
├── immich-native/           # Photo management (native NixOS)
├── frigate/                 # NVR surveillance
├── youtube/                 # YouTube services
│
├── downloaders/             # Download infrastructure
├── orchestration/           # Media pipeline orchestration
└── media-native/            # Native media service aggregator
```

### Workspace Support (`workspace/media/`)

```
workspace/media/
├── youtube-services/      # YT packages + transcript formatter (referenced by youtube/parts/*.nix)
│   ├── packages/          # yt_core, yt_transcripts_api, yt_videos_api
│   └── transcript-formatter/
├── scripts/               # beets helpers, media organizer, migration scripts
├── hooks/                 # Media-specific event hooks
├── config-examples/       # Reference configurations
├── cleanup-raw-files/     # Raw file cleanup tool
└── n8n-workflows/         # Media-related n8n workflow JSON configs
```

## Changelog
- 2026-08-01: readarr — realigned container mounts so `/books` denotes the same host directory in readarr as it does in calibre (`media.books/ebooks`), and gave audiobooks their own `/audiobooks` token. readarr previously mounted `media.books` one level up, so the *same* `/books` prefix resolved to two different host roots across the two containers. Readarr asks the calibre content server where it filed an import, receives a path in calibre's namespace (`/books/calibre`), and resolves it in its own — the two never agreed, so the root-folder health check failed and **every book import from 2026-02-27 onward landed as `bookImportIncomplete`**. Root folders and the 8 author paths were migrated to the new vocabulary (runtime state, not in repo).
- 2026-08-01: scripts — `hot-sweep` now consults **both** download clients before deleting. It previously derived "orphan" solely from qBittorrent's torrent list while SABnzbd writes into the same `/mnt/hot/downloads/{tv,movies,music}` tree, so any usenet download not imported within `MIN_AGE_H` was `rmtree`'d out from under the importer. Added `sab_active()` (queue + history, API key read from `sabnzbd.ini` at runtime — never interpolated into the world-readable store) and a hard bail-out that skips **all** categories when SABnzbd is unreachable, matching the existing fail-safe for qBittorrent. No sweep may run on a partial view of who owns what.
- 2026-08-01: qbittorrent — DHT + PeX re-enabled by default via new per-protocol `privacy.*` toggles; see that domain's README for the rationale and the private-tracker analysis.
- 2026-07-16: recyclarr — HD-1080p profiles (Sonarr + Radarr) extended with a full fallback ladder (720p → SD/DVD) with upgrade-until-Bluray-1080p, so DVD-only content (e.g. Look Around You) downloads instead of being rejected with "DVD is not wanted in profile". Jellyseerr defaults + existing library migrated to the managed profile via API (runtime state, not in repo).
- 2026-07-16: jellyfin-native — revived declarative user-policy service with `apiKeyFile` (agenix path, replaces the removed plaintext `apiKey` option) and new per-user `passwordless`/`hidden`/`admin`/`ensure`+`passwordFile` options. Jellyfin 10.11 forbids passwordless admins, so server config now ensures a hidden `admin` account (jellyfin-admin-password.age) and demotes eric + Kids to regular passwordless tap-to-sign-in profiles.
- 2026-07-06: audiobookshelf image pinned to 2.32.1 (Law 15 v12.4 critical tier: library state).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-07-05: Removed `youtube.legacyApi` entirely (option block, `parts/legacy-api.nix`, server config stanza, prometheus scrape block) — superseded by yt-transcripts-api v2, never enabled, and its scriptDir pointed at a path deleted in the 2026-03 workspace restructure. media-orchestrator's deploy step repointed from the removed stale `workspace/hooks/` fork to the canonical `workspace/automation/hooks/`.
- 2026-06-09: Law 9/10 — `orchestration/media-orchestrator.nix` → `orchestration/media-orchestrator/index.nix` (pure relocation).
- 2026-06-09: Law 3 finish — youtube transcripts outputDirectory derives from `hwc.paths.media.root` (null-safe); legacyApi dataDir derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-03-26: workspace/youtube-services/ moved to workspace/media/youtube-services/ (domain alignment); audiobook-copier path updated to workspace/automation/hooks/
- 2026-03-04: Namespace migration hwc.server.{containers,native}.* → hwc.media.*
- 2026-03-04: Created media domain; moved all media containers and native services from domains/server/ (Phase 7 of DDD migration)
