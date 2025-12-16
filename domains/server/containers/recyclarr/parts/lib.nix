{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.recyclarr;
in
{
  config = lib.mkIf cfg.enable {
    # Ensure recyclarr-sync depends on config setup
    systemd.services.recyclarr-sync = {
      after = [ "recyclarr-config-setup.service" ];
      wants = [ "recyclarr-config-setup.service" ];
    };
  };
}
