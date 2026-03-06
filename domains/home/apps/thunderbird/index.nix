# domains/home/apps/thunderbird/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.thunderbird;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.thunderbird = {
    enable = lib.mkEnableOption "Thunderbird email client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.thunderbird ];
  };
}
