# modules/home/apps/kitty/options.nix
{ lib, ... }:

{
  options.features.kitty.enable =
    lib.mkEnableOption "Enable Kitty terminal emulator";
}