{ lib, ... }:

{
  options.hwc.home.apps.dosbox = {
    enable = lib.mkEnableOption "DOS emulator";
  };
}
