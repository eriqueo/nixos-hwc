{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.slskd;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "slskd";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = ["127.0.0.1:5030:5030"];
      volumes = [ "/opt/downloads/slskd:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
    { # publish caddy route
      hwc.services.shared.routes = lib.mkAfter [
        (shared.mkRoute { path = "/slskd"; upstream = "127.0.0.1:5030"; stripPrefix = false; })
      ];
    }
  ]);
}
