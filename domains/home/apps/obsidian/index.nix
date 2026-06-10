# domains/home/apps/obsidian/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.obsidian;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.obsidian = {
    enable = lib.mkEnableOption "Obsidian note-taking app";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.obsidian ];
  };
}
