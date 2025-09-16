# modules/home/apps/betterbird/options.nix
{ lib, ... }:

{
  options.features.betterbird.enable =
    lib.mkEnableOption "Enable Betterbird (enhanced Thunderbird)";
}