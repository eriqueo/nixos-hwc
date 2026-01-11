{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.yazi = {
    enable = lib.mkEnableOption "Blazing fast terminal file manager written in Rust, based on async I/O";
  };
}