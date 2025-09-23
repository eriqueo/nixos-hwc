{ lib, ... }:

{
  options.hwc.home.apps.aerc = {
    enable = lib.mkEnableOption "Email client for your terminal";
  };
}
