# domains/system/hardware/options.nix
# Feature toggle for system hardware aggregation

{ lib, ... }:
{
  options.hwc.system.hardware = {
    enable = lib.mkEnableOption "system hardware aggregation" // { default = true; };
  };
}
