{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.caddy;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "caddy";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = [];
      volumes = [ "/opt/downloads/caddy:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })

  ]);
}
