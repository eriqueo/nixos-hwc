# HWC Container Services Aggregator
# Imports all container services and shared infrastructure

{ lib, config, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    # Legacy namespace compatibility: hwc.server.containers.* → hwc.server.containers.*
    (lib.mkRenamedOptionModule [ "hwc" "services" "containers" ] [ "hwc" "server" "containers" ])

    # Shared infrastructure (caddy.nix and network.nix moved to domains/networking/)
    ./_shared/directories.nix

    # Container services (gluetun, pihole moved to domains/networking/)
    ./audiobookshelf/index.nix
    ./beets/index.nix
    ./mousehole/index.nix
    ./books/index.nix
    ./caddy/index.nix
    ./calibre/index.nix
    ./immich/index.nix
    ./jellyfin/index.nix
    ./jellyseerr/index.nix
    ./lidarr/index.nix
    ./navidrome/index.nix
    ./organizr/index.nix
    ./pinchflat/index.nix
    ./prowlarr/index.nix
    ./paperless/index.nix
    ./qbittorrent/index.nix
    ./radarr/index.nix
    ./readarr/index.nix
    ./recyclarr/index.nix
    ./sabnzbd/index.nix
    ./slskd/index.nix
    ./sonarr/index.nix
    ./soularr/index.nix
    ./tdarr/index.nix
    ./firefly/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
