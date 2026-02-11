# domains/home/apps/imv/index.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.imv;
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      imv
    ];
  };
}
