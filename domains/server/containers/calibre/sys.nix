{ lib, config, pkgs, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.calibre;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/calibre/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "calibre";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [
        "127.0.0.1:8083:8080"  # Desktop interface (Selkies web, default 8080)
        "127.0.0.1:8090:8090"  # Content Server (direct, no nginx)
      ];
      volumes = [
        "${configPath}:/config"
        "${cfg.libraries.ebooks}:/books/ebooks"
        "${cfg.libraries.audiobooks}:/books/audiobooks"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        CALIBRE_USE_DARK_PALETTE = "1";
      };
      
            dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
          })
        ]);
}
