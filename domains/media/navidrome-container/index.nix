{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.navidrome;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.navidrome = {
    enable = lib.mkEnableOption "navidrome container";
    image = lib.mkOption { type = lib.types.str; default = "deluan/navidrome:latest"; description = "Container image"; };
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
