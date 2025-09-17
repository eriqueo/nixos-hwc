# modules/home/apps/dunst/options.nix
{ lib, ... }:

{
  options.features.dunst.enable =
    lib.mkEnableOption "Enable dunst notification daemon";
}