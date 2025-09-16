{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.qbittorrent;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "qbittorrent";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = [];
      volumes = [ "/opt/downloads/qbittorrent:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    { # publish caddy route
      hwc.services.shared.routes = lib.mkAfter [
        (shared.mkRoute { path = "/qbt"; upstream = "127.0.0.1:8080"; stripPrefix = false; })
      ];
    }
  ]);
}
