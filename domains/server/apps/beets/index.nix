{ config, pkgs, ... }:

let
  cfg = config.hwc.server.apps.beets;
in
{
  config = {
    virtualisation.oci-containers.containers.beets = {
      image = cfg.image;
      volumes = [
        "${cfg.configDir}:/config"
        "${cfg.musicDir}:/music"
      ];
      environment = {
        PUID = "1000";
        PGID = "100";
        TZ = "America/New_York";
      };
    };
  };
}
