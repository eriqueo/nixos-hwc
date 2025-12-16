{ lib, ... }:

{
  options.hwc.home.apps.mpv = {
    enable = lib.mkEnableOption "Enable MPV media player";
  };
}
