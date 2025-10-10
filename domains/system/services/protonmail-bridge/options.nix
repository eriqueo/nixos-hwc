{ lib, ... }:
{
  options.hwc.system.services.protonmail-bridge = {
    enable = lib.mkEnableOption "Proton Mail Bridge system service";
  };
}