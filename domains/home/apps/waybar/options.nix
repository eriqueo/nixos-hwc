# modules/home/apps/waybar/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.waybar.enable =
    lib.mkEnableOption "Enable Waybar";
}