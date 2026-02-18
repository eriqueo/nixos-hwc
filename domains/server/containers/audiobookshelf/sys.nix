# domains/server/containers/audiobookshelf/sys.nix
{ lib, config, pkgs, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.audiobookshelf;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/audiobookshelf/config";
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
        "${configPath}:/config"
        "${cfg.library}:/audiobooks"
        "${cfg.podcasts}:/podcasts"
        "${cfg.metadata}:/metadata"
      ];
      environment = {};
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
    })
  ]);
}
