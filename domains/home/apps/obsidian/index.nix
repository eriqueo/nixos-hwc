# domains/home/apps/obsidian/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.obsidian;
in
{
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.obsidian ];
  };
}
