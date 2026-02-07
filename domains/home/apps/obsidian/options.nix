# modules/home/apps/obsidian/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.obsidian.enable =
    lib.mkEnableOption "Enable Obsidian knowledge management app";
}