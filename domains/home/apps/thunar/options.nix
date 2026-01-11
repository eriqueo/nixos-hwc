# modules/home/apps/thunar/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.thunar.enable =
    lib.mkEnableOption "Enable Thunar file manager";
}