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
      # 1. REMOVE PORTS - Gluetun handles these now
            ports = []; 
      
            volumes = [
              "${configPath}:/config"
              "${cfg.libraries.ebooks}:/books/ebooks"
              "${cfg.libraries.audiobooks}:/books/audiobooks"
              "${config.hwc.paths.hot.root}/downloads:/downloads"
            ];
      
            environment = {
              CALIBRE_USE_DARK_PALETTE = "1";
              # 2. SHIFT INTERNAL PORTS
              # Force Desktop UI to 8082 (avoids 8080 conflict with qBit)
              CUSTOM_PORT = "8082"; 
              # Force Content Server to 8090
              CALIBRE_SERVER_PORT = "8090"; 
            };
      
            dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [];
          })
        ]);
}
