{ lib, ... }:

{
  options.hwc.home.apps.opencode = {
    enable = lib.mkEnableOption "AI coding agent built for the terminal";
  };
}
