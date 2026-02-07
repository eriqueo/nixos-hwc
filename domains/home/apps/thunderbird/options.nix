{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.thunderbird = {
    enable = lib.mkEnableOption "Full-featured e-mail client";
  };
}