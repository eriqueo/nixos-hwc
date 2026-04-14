# domains/home/apps/swaync/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.swaync;
  appearance = import ./parts/appearance.nix { inherit config lib pkgs; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.swaync = {
    enable = lib.mkEnableOption "SwayNC notification center";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.swaynotificationcenter ];

    services.swaync = {
      enable = true;
      settings = appearance.settings;
      style = appearance.style;
    };
  };
}