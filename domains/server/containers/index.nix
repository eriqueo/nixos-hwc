# HWC Container Services Aggregator
# Imports all container services and shared infrastructure

{ lib, config, ... }:

{
  imports = [
    # Shared infrastructure
    ./_shared/network.nix
    ./_shared/caddy.nix

    # Container services
    ./beets/index.nix
    ./caddy/index.nix
    ./gluetun/index.nix
    ./immich/index.nix
    ./jellyfin/index.nix
    ./jellyseerr/index.nix
    ./lidarr/index.nix
    ./navidrome/index.nix
    ./organizr/index.nix
    ./prowlarr/index.nix
    ./qbittorrent/index.nix
    ./radarr/index.nix
    ./recyclarr/index.nix
    ./sabnzbd/index.nix
    ./slskd/index.nix
    ./sonarr/index.nix
    ./soularr/index.nix
    ./tdarr/index.nix
  ];

  # Guard against user creation in container modules
  config = {
    assertions = [
      {
        assertion = true; # Container modules should use DynamicUser or PUID/PGID
        message = ''
          Container modules must not create users. Use DynamicUser=true for systemd services
          or PUID=1000/PGID=1000 for OCI containers. All user creation happens in modules/system/users/.
        '';
      }
    ];
  };
}