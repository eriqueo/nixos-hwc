# Jellyseerr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" "agenix.service" ];

    # Publish reverse proxy route
    hwc.services.shared.routes = lib.mkAfter [
      {
        path = "/jellyseerr";
        upstream = "127.0.0.1:5055";
        stripPrefix = false;
      }
    ];
  };
}
