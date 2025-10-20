# Sonarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.sonarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-sonarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-sonarr".wants = [ "network-online.target" "agenix.service" ];

    # Publish reverse proxy route
    hwc.services.shared.routes = lib.mkAfter [
      {
        path = "/sonarr";
        upstream = "127.0.0.1:8989";
        stripPrefix = false;
      }
    ];
  };
}
