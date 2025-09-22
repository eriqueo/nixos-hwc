# modules/home/fonts/options.nix
# Font domain options

{ lib, ... }:

{
  options.hwc.home.fonts = {
    enable = lib.mkEnableOption "Enable HWC font management for user environment";
  };
}