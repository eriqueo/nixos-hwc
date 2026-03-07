{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.jellyseerr = {
    enable = lib.mkEnableOption "jellyseerr container";
    image = lib.mkOption { type = lib.types.str; default = "docker.io/fallenbagel/jellyseerr:latest"; description = "Container image"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/setup.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
