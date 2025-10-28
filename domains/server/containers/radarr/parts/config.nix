# Radarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.radarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];

    # Publish reverse proxy route
    hwc.services.shared.routes = lib.mkAfter [
      {
        path = "/radarr";
        upstream = "127.0.0.1:7878";
        stripPrefix = false;
      }
    ];
  };
}
