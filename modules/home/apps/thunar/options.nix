# modules/home/apps/thunar/options.nix
{ lib, ... }:

{
  options.features.thunar.enable =
    lib.mkEnableOption "Enable Thunar file manager";
}