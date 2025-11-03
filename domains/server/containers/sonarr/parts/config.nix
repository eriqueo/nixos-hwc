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


  };
}
