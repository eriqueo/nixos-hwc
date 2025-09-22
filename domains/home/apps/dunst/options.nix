# modules/home/apps/dunst/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.dunst.enable =
    lib.mkEnableOption "Enable dunst notification daemon";
}