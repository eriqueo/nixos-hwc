{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-jellyseerr".wants  = [ "network-online.target" "agenix.service" ];
  };
}
