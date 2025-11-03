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


  };
}
