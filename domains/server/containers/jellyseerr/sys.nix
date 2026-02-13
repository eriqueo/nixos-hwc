{ lib, pkgs, config, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  appRoot = "${appsRoot}/jellyseerr";
  configPath = "${appRoot}/config";
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
        "${configPath}:/app/config:rw"
      ];
      environment = { };
      extraOptions = [ ];
      dependsOn = [ "sonarr" "radarr" ];
      user = "1000:100";
    })
    {
      systemd.tmpfiles.rules = [
        "d ${appsRoot} 0755 root root -"
        "d ${appRoot} 0755 1000 100 -"
        # Config directory and settings.json created in parts/config.nix
      ];
    }
  ]);
}
