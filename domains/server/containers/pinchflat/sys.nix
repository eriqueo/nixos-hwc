{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.pinchflat;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/pinchflat/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "pinchflat";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;  # Pinchflat doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:8945" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.media.root}/youtube:/downloads"
      ];
      environment = {};  # Runs at root, Caddy strips /pinch prefix
      dependsOn = [];  # No dependencies - standalone service
    })

    # Create required directories
    {
      systemd.tmpfiles.rules = [
        "d ${configPath} 0755 1000 100 -"
        "d ${config.hwc.paths.media.root}/youtube 0755 1000 100 -"
      ];
    }
  ]);
}
