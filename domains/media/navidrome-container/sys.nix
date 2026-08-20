{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.navidrome;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/navidrome/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "navidrome";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = "UTC";   # Static default - timezone detection deferred
      ports = [ "127.0.0.1:4533:4533" ];
      volumes = [
        "${configPath}:/config"
        "${config.hwc.paths.media.root}/music:/music:ro"  # Music library for streaming
      ];
      environment = {
        # Empty: navidrome serves at the root of its own vhost
        # (navidrome.<vhostDomain>). A non-empty base here does not just add a
        # prefix — navidrome 302s root to it, so a stale value would bounce
        # every vhost request to a path the vhost does not route.
        ND_BASEURL = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
  ]);
}
