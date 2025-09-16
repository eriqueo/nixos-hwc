{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.immich;
in
{
  options.hwc.services.containers.immich = {
    enable = mkEnableOption "immich container";
    image  = shared.mkImageOption { default = "ghcr.io/immich-app/immich-server:latest"; description = "Container image"; };
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
