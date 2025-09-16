{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.gluetun;
in
{
  options.hwc.services.containers.gluetun = {
    enable = mkEnableOption "gluetun container";
    image  = shared.mkImageOption { default = "qmcgaw/gluetun:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };

  imports = [
    ./parts/sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  config = mkIf cfg.enable { };
}
