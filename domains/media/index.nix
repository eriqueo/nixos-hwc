# domains/media/index.nix
#
# Media domain — streaming, acquisition, processing, photos, video.
# The largest domain, encompassing all media-related services.
#
# Namespace: hwc.media.*

{ lib, config, ... }:

{
  imports = [
    # ── Streaming ──────────────────────────────────────────────
    ./jellyfin-native/index.nix       # native NixOS service (services.jellyfin)
    ./navidrome-container/index.nix   # podman container
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
    ./beets-container/index.nix       # podman container (hwc.media.beets)
    ./recyclarr/index.nix
    ./slskd/index.nix
    ./soularr/index.nix
    ./calibre/index.nix
    ./books/index.nix

    # ── Photos & Video ─────────────────────────────────────────
    ./immich-container/index.nix      # podman container
    ./frigate/index.nix
    ./youtube/index.nix

    # ── Infrastructure ─────────────────────────────────────────
    ./downloaders/index.nix
    ./orchestration/index.nix
    ./media-native/index.nix
    ./directories.nix
  ];
}
