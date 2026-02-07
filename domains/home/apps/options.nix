# domains/home/apps/options.nix
# Toggle for importing all home apps

{ lib, osConfig ? {}, ... }:
{
  options.hwc.home.apps = {
    enable = lib.mkEnableOption "home apps aggregation" // { default = true; };
  };
}