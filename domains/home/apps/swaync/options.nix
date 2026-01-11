# domains/home/apps/swaync/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.swaync = {
    enable = lib.mkEnableOption "SwayNotificationCenter - notification daemon and center";
  };
}