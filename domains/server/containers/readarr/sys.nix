{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.readarr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/readarr/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "readarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:8787:8787" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.media.root}/books:/books"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        READARR__URLBASE = "/readarr";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
  ]);
}
