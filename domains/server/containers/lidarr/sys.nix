{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.services.containers.lidarr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "lidarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:8686:8686" ];
      volumes = [
        "/opt/downloads/lidarr:/config"
        "${config.hwc.paths.media}/music:/music"
        "${config.hwc.paths.hot}/downloads:/downloads"
      ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
  ]);
}
