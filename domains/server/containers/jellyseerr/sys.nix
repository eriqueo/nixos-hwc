{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
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
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:5055:5055" ];
      volumes = [
        "/opt/downloads/jellyseerr:/config"
      ];
      environment = { };
      dependsOn = [ "jellyfin" "sonarr" "radarr" ];
    })
  ]);
}
