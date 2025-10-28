# Lidarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.lidarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-lidarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-lidarr".wants = [ "network-online.target" "agenix.service" ];

    # Publish reverse proxy route
    hwc.services.shared.routes = lib.mkAfter [
      {
        path = "/lidarr";
        upstream = "127.0.0.1:8686";
        stripPrefix = false;
      }
    ];
  };
}
