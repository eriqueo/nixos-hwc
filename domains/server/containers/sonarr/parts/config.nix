# Sonarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.sonarr;
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-sonarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-sonarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-sonarr".requires = [ "mnt-hot.mount" ];


  };
}
