{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.navidrome;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "navidrome";
      image = cfg.image;
      pull = if cfg.image == cfg._runtimeImage then "never" else "missing";
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = "UTC";   # Static default - timezone detection deferred
      ports = [ "127.0.0.1:${toString cfg.port}:4533" ];
      volumes = [
        "${cfg.dataDir}:/data"
        "${config.hwc.paths.media.root}/music:/music:ro"  # Music library for streaming
      ];
      extraOptions = [ "--security-opt=no-new-privileges" ];
      environment = {
        # Empty: navidrome serves at the root of its own vhost
        # (navidrome.<vhostDomain>). A non-empty base here does not just add a
        # prefix — navidrome 302s root to it, so a stale value would bounce
        # every vhost request to a path the vhost does not route.
        ND_BASEURL = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    (lib.mkIf config.hwc.data.borg.enable {
      hwc.data.borg.sqliteSnapshots.navidrome = {
        source = "${cfg.dataDir}/navidrome.db";
        user = "root";
      };
      hwc.data.borg.sources = [ cfg.dataDir ];
    })
  ]);
}
