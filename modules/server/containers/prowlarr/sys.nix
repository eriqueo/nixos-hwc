{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.prowlarr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "prowlarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = ["127.0.0.1:9696:9696"];
      volumes = [ "/opt/downloads/prowlarr:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    { # publish caddy route
      hwc.services.shared.routes = lib.mkAfter [
        (shared.mkRoute { path = "/prowlarr"; upstream = "127.0.0.1:9696"; stripPrefix = false; })
      ];
    }
  ]);
}
