{ lib, pkgs, config, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "jellyseerr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:5055:5055" ];
      volumes = [
        "/opt/jellyseerr/config:/app/config:rw"
      ];
      environment = { };
      extraOptions = [ ];
      dependsOn = [ "sonarr" "radarr" ];
      user = "1000:1000";
    })
    {
      systemd.tmpfiles.rules = [
        "d /opt 0755 root root -"
        "d /opt/jellyseerr 0755 1000 1000 -"
        "d /opt/jellyseerr/config 0755 1000 1000 -"
      ];
    }
  ]);
}
