# domains/media/audiobookshelf/sys.nix
{ lib, config, pkgs, ... }:
let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.audiobookshelf;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "audiobookshelf";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;  # Audiobookshelf doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.library}:/audiobooks"
        "${cfg.podcasts}:/podcasts"
        "${cfg.metadata}:/metadata"
      ];
      environment = {};
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
    })
    (lib.mkIf config.hwc.data.borg.enable {
      # The pinned application and its database run as root despite PUID.
      # Match the actual source owner; do not change application permissions.
      hwc.data.borg.sqliteSnapshots.audiobookshelf = {
        source = "${cfg.dataDir}/absdatabase.sqlite";
        user = "root";
      };
      # Keep token/config identity and cover metadata beside the ready DB.
      # Original audiobook media remains under its existing storage policy.
      hwc.data.borg.sources = [ cfg.dataDir (toString cfg.metadata) ];
    })
  ]);
}
