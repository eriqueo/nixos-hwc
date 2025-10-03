{ lib, ... }:

{
  options.hwc.home.apps.wasistlos = {
    enable = lib.mkEnableOption "Unofficial WhatsApp desktop application";
  };
}
