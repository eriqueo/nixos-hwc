{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.soularr;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "soularr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = [];
      volumes = [ "/opt/downloads/soularr:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })

  ]);
}
