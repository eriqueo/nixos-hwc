{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.tdarr;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-tdarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-tdarr".wants  = [ "network-online.target" "agenix.service" ];
  };
}
