{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.sonarr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "sonarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:8989:8989" ];
      volumes = [
        "${config.hwc.paths.hot.downloads}/sonarr:/config"
        "${config.hwc.paths.media.root}/tv:/tv"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        SONARR__URLBASE = "/sonarr";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
  ]);
}
