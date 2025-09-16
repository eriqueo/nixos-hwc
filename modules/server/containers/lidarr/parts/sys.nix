{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.lidarr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "lidarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = ["127.0.0.1:8686:8686"];
      volumes = [ "/opt/downloads/lidarr:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    { # publish caddy route
      hwc.services.shared.routes = lib.mkAfter [
        (shared.mkRoute { path = "/lidarr"; upstream = "127.0.0.1:8686"; stripPrefix = false; })
      ];
    }
  ]);
}
