# Radarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.radarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-radarr".requires = [ "mnt-hot.mount" ];


  };
}
