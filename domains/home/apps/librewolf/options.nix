# modules/home/apps/librewolf/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.librewolf.enable =
    lib.mkEnableOption "Enable LibreWolf (privacy-focused Firefox fork)";
}