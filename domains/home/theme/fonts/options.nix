# modules/home/fonts/options.nix
# Font domain options

{ lib, ... }:

{
  options.hwc.home.theme.fonts = {
    enable = lib.mkEnableOption "Enable HWC font management for user environment";
  };
}