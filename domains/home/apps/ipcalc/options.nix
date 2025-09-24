{ lib, ... }:

{
  options.hwc.home.apps.ipcalc = {
    enable = lib.mkEnableOption "Simple IP network calculator";
  };
}
