# modules/home/apps/kitty/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.kitty.enable =
    lib.mkEnableOption "Enable Kitty terminal emulator";
}