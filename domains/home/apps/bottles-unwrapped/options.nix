{ lib, ... }:

{
  options.hwc.home.apps.bottles-unwrapped = {
    enable = lib.mkEnableOption "Easy-to-use wineprefix manager";
  };
}
