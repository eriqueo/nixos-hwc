# domains/home/apps/swaync/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:

let
  enabled = config.hwc.home.apps.swaync.enable or false;

  appearance = import ./parts/appearance.nix { inherit config lib pkgs; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    home.packages = with pkgs; [ swaynotificationcenter ];

    services.swaync = {
      enable = true;
      settings = appearance.settings;
      style = appearance.style;
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}