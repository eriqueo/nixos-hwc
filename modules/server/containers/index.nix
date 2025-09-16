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
    ./caddy
    ./gluetun
    ./immich
    ./jellyfin
    ./lidarr
    ./navidrome
    ./prowlarr
    ./qbittorrent
    ./radarr
    ./sabnzbd
    ./slskd
    ./sonarr
    ./soularr
  ];
}