# modules/home/apps/waybar/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.waybar.enable =
    lib.mkEnableOption "Enable Waybar";
}