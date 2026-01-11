# modules/home/apps/chromium/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.chromium = {
    enable = lib.mkEnableOption "Chromium browser (user-scoped package)";
  };
}