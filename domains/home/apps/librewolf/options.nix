# modules/home/apps/librewolf/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.librewolf.enable =
    lib.mkEnableOption "Enable LibreWolf (privacy-focused Firefox fork)";
}