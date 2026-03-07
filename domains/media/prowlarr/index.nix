{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.prowlarr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.prowlarr = {
    enable = lib.mkEnableOption "prowlarr container";
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/prowlarr:latest"; description = "Container image"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
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
