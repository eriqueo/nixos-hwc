{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.localsend = {
    enable = lib.mkEnableOption "Open source cross-platform alternative to AirDrop";
  };
}