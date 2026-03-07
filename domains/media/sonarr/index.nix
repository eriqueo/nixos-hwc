{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.sonarr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.sonarr = {
    enable = lib.mkEnableOption "sonarr container";
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/sonarr:latest"; description = "Container image"; };
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
