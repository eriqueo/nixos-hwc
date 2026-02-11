{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.imv = {
    enable = lib.mkEnableOption "A command-line image viewer for X11/Wayland.";
  };
}
