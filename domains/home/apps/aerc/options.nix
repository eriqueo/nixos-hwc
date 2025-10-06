{ lib, ... }:

{
  options.hwc.home.apps.aerc = {
    enable = lib.mkEnableOption "Email client for your terminal";

    sieve.filters = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = "Sieve filename -> script text, written into ~/.config/aerc/sieve/filters/";
    };
  };
}
