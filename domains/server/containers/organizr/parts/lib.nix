{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.organizr;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-organizr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-organizr".wants  = [ "network-online.target" "agenix.service" ];
  };
}
