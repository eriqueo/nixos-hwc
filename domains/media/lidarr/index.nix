{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.lidarr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.lidarr = {
    enable = lib.mkEnableOption "lidarr container";
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/lidarr:2.13.3";
      description = "Container image (pinned version - develop branch has NullRef bug in Distance.Clean())";
    };
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
