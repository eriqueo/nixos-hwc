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

## Changelog

- 2026-03-04: Created media domain; moved all media containers and native services from domains/server/ (Phase 7 of DDD migration)
