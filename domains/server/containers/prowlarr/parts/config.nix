# Prowlarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.prowlarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-prowlarr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-prowlarr".wants = [ "network-online.target" ];

    # Publish reverse proxy route
    hwc.services.shared.routes = lib.mkAfter [
      {
        path = "/prowlarr";
        upstream = "127.0.0.1:9696";
        stripPrefix = false;
      }
    ];
  };
}
