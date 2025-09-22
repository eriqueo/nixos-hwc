# modules/home/apps/chromium/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.chromium = {
    enable = lib.mkEnableOption "Chromium browser (user-scoped package)";
  };
}