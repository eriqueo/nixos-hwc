{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.sonarr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "sonarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = ["127.0.0.1:8989:8989"];
      volumes = [ "/opt/downloads/sonarr:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    { # publish caddy route
      hwc.services.shared.routes = lib.mkAfter [
        (shared.mkRoute { path = "/sonarr"; upstream = "127.0.0.1:8989"; stripPrefix = false; })
      ];
    }
  ]);
}
