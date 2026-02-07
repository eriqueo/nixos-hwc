# domains/home/core/options.nix
# Toggle for core home modules

{ lib, osConfig ? {}, ... }:
{
  options.hwc.home.core = {
    enable = lib.mkEnableOption "core home configuration" // { default = true; };
  };
}