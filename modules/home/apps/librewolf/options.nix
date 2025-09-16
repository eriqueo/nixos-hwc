# modules/home/apps/librewolf/options.nix
{ lib, ... }:

{
  options.features.librewolf.enable =
    lib.mkEnableOption "Enable LibreWolf (privacy-focused Firefox fork)";
}