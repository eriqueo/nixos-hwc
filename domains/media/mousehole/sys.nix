# domains/server/containers/mousehole/sys.nix
{ lib, config, pkgs, ... }:
let
  # Import PURE helper library
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.media.mousehole;
  appsRoot = config.hwc.paths.apps.root;
  dataPath = "${appsRoot}/mousehole/data";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using mkContainer
    (mkContainer {
      name = "mousehole";
      image = cfg.image;
      networkMode = "vpn";  # Runs inside gluetun's network namespace
      gpuEnable = false;
      timeZone = config.time.timeZone or "UTC";

      # Resource limits (lighter than default)
      memory = "256m";
      cpus = "0.25";
      memorySwap = "512m";

      environment = {
        MOUSEHOLE_PORT = toString cfg.port;
        MOUSEHOLE_STATE_DIR_PATH = "/srv/mousehole";
        MOUSEHOLE_CHECK_INTERVAL_SECONDS = toString cfg.checkInterval;
        MOUSEHOLE_STALE_RESPONSE_SECONDS = toString cfg.staleResponseSeconds;
      };

      volumes = [
        "${dataPath}:/srv/mousehole"
      ];

      dependsOn = [ "gluetun" ];
    })
  ]);
}
