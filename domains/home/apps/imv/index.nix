# domains/home/apps/imv/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.imv;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.imv = {
    enable = lib.mkEnableOption "imv image viewer";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.imv ];
  };
}
