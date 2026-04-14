{ lib, config, pkgs, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.organizr = {
    enable = lib.mkEnableOption "Organizr unified dashboard";
    image = lib.mkOption { type = lib.types.str; default = "organizr/organizr:latest"; description = "Container image for Organizr"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    webPort = lib.mkOption { type = lib.types.port; default = 9983; description = "Web UI port"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU acceleration"; };
  };

  imports = [
    ./parts/config.nix
    ./parts/setup.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
