# modules/home/apps/chromium/options.nix
{ lib, ... }:

{
  options.features.chromium = {
    enable = lib.mkEnableOption "Chromium browser (user-scoped package)";
  };

  options.hwc.infrastructure.session.chromium = {
    enable = lib.mkEnableOption "Chromium browser system integration (portals, dbus, dconf support)";
  };
}