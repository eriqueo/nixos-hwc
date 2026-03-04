# domains/media/index.nix
#
# Media domain — streaming, acquisition, processing, photos, video.
# The largest domain, encompassing all media-related services.
#
# Namespace: hwc.server.containers.*, hwc.server.native.*
# TODO Phase 8: Migrate to hwc.media.*

{ lib, config, ... }:

{
  imports = [
    # ── Streaming ──────────────────────────────────────────────
    ./jellyfin-container/index.nix
    ./jellyfin-native/index.nix
    ./navidrome-container/index.nix
    ./navidrome-native/index.nix
    ./audiobookshelf/index.nix
    ./jellyseerr/index.nix

    # ── Acquisition (*arr + download clients) ──────────────────
    ./sonarr/index.nix
    ./radarr/index.nix
    ./lidarr/index.nix
    ./prowlarr/index.nix
    ./readarr/index.nix
    ./qbittorrent/index.nix
    ./sabnzbd/index.nix

    # ── Processing & Utilities ─────────────────────────────────
    ./tdarr/index.nix
    ./organizr/index.nix
    ./mousehole/index.nix
    ./pinchflat/index.nix
    ./beets-container/index.nix
    ./beets-native/index.nix
    ./recyclarr/index.nix
    ./slskd/index.nix
    ./soularr/index.nix
    ./calibre/index.nix
    ./books/index.nix

    # ── Photos & Video ─────────────────────────────────────────
    ./immich-container/index.nix
    ./immich-native/index.nix
    ./frigate/index.nix
    ./youtube/index.nix

    # ── Infrastructure ─────────────────────────────────────────
    ./downloaders/index.nix
    ./orchestration/index.nix
    ./media-native/index.nix
  ];
}
