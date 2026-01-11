# modules/home/fonts/options.nix
# Font domain options

{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.fonts = {
    enable = lib.mkEnableOption "Enable HWC font management for user environment";
  };
}