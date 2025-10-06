# modules/home/apps/obsidian/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.obsidian.enable =
    lib.mkEnableOption "Enable Obsidian knowledge management app";
}