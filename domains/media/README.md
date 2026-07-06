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
- 2026-07-06: Law 12 child-README sweep — refreshed the `frigate/`, `immich-container/`, and `youtube/` module READMEs to match current code (Law 5 exception annotation, external-library mount swap, legacy/videos-API removal). No media-index code change.
- 2026-07-06: audiobookshelf image pinned to 2.32.1 (Law 15 v12.4 critical tier: library state).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-07-05: Removed `youtube.legacyApi` entirely (option block, `parts/legacy-api.nix`, server config stanza, prometheus scrape block) — superseded by yt-transcripts-api v2, never enabled, and its scriptDir pointed at a path deleted in the 2026-03 workspace restructure. media-orchestrator's deploy step repointed from the removed stale `workspace/hooks/` fork to the canonical `workspace/automation/hooks/`.
- 2026-06-09: Law 9/10 — `orchestration/media-orchestrator.nix` → `orchestration/media-orchestrator/index.nix` (pure relocation).
- 2026-06-09: Law 3 finish — youtube transcripts outputDirectory derives from `hwc.paths.media.root` (null-safe); legacyApi dataDir derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-03-26: workspace/youtube-services/ moved to workspace/media/youtube-services/ (domain alignment); audiobook-copier path updated to workspace/automation/hooks/
- 2026-03-04: Namespace migration hwc.server.{containers,native}.* → hwc.media.*
- 2026-03-04: Created media domain; moved all media containers and native services from domains/server/ (Phase 7 of DDD migration)
