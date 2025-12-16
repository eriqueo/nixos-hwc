# domains/system/storage/options.nix
# Feature toggle for system storage aggregation

{ lib, ... }:
{
  options.hwc.system.storage = {
    enable = lib.mkEnableOption "system storage aggregation" // { default = true; };
  };
}
