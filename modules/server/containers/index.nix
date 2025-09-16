# HWC Container Services Aggregator
# Imports all container services and shared infrastructure

{ lib, ... }:

{
  imports = [
    # Shared infrastructure
    ./_shared/lib.nix
    ./_shared/network.nix
    ./_shared/caddy.nix
    
    # Container services
    ./caddy/index.nix
    ./gluetun/index.nix
    ./immich/index.nix
    ./jellyfin/index.nix
    ./lidarr/index.nix
    ./navidrome/index.nix
    ./prowlarr/index.nix
    ./qbittorrent/index.nix
    ./radarr/index.nix
    ./sabnzbd/index.nix
    ./slskd/index.nix
    ./sonarr/index.nix
    ./soularr/index.nix
  ];
}