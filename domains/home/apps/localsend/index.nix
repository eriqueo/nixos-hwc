# domains/home/apps/localsend/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.localsend;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.localsend = {
    enable = lib.mkEnableOption "LocalSend file sharing";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.localsend ];
  };
}
