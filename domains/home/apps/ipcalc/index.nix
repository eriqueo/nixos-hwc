# domains/home/apps/ipcalc/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.ipcalc;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.ipcalc = {
    enable = lib.mkEnableOption "ipcalc IP calculator";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.ipcalc ];
  };
}
