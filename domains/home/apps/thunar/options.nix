# modules/home/apps/thunar/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.thunar.enable =
    lib.mkEnableOption "Enable Thunar file manager";
}