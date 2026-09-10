{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.pinchflat;
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
      pull = "newer";  # Pull newer images on rebuild (keeps yt-dlp updated)
    })

    # Create required directories
    {
      # ${media.root}/youtube is NOT declared here: it is a shared library
      # directory that the youtube transcripts service also writes to, and both
      # modules used to declare it with different owner spellings. It now comes
      # from domains/media/directories.nix, the single producer.
      systemd.tmpfiles.rules = [
        "d ${configPath} 0755 1000 100 -"
      ];
    }
  ]);
}
