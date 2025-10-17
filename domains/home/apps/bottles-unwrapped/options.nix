{ lib, ... }:

{
  options.hwc.home.apps.bottlesUnwrapped = {
    enable = lib.mkEnableOption "Easy-to-use wineprefix manager";
  };
}
