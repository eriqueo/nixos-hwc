{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.services.containers.caddy;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "caddy";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";  # Static default - GPU detection deferred
      timeZone = "UTC";   # Static default - timezone detection deferred
      ports = [];
      volumes = [ "/opt/downloads/caddy:/config" ];
      environment = { };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    })
  ]);
}
