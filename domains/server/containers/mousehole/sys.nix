# domains/server/containers/mousehole/sys.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.mousehole;
  appsRoot = config.hwc.paths.apps.root;
  dataPath = "${appsRoot}/mousehole/data";
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.mousehole = {
      image = cfg.image;
      autoStart = true;

      # Run inside gluetun's network namespace (shares VPN tunnel)
      extraOptions = [
        "--network=container:gluetun"
        "--memory=256m"
        "--cpus=0.25"
      ];

      environment = {
        TZ = config.time.timeZone or "UTC";
        MOUSEHOLE_PORT = toString cfg.port;
        MOUSEHOLE_STATE_DIR_PATH = "/srv/mousehole";
        MOUSEHOLE_CHECK_INTERVAL_SECONDS = toString cfg.checkInterval;
        MOUSEHOLE_STALE_RESPONSE_SECONDS = toString cfg.staleResponseSeconds;
      };

      volumes = [
        "${dataPath}:/srv/mousehole"
      ];

      dependsOn = [ "gluetun" ];
    };
  };
}
