# Lidarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.lidarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-lidarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-lidarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-lidarr".requires = [ "mnt-hot.mount" ];


  };
}
