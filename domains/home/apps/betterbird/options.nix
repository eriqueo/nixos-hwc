# modules/home/apps/betterbird/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.betterbird.enable =
    lib.mkEnableOption "Enable Betterbird (enhanced Thunderbird)";
}