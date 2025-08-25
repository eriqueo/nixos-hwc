{ lib, ... }:
let t = lib.types;
in {
  options.hwc.home.waybar = {
    enable   = lib.mkEnableOption "Waybar status bar";
    position = lib.mkOption { type = t.enum [ "top" "bottom" ]; default = "top"; };
    theme    = lib.mkOption { type = t.str; default = "deep-nord"; };
    modules = {
      gpu = {
        enable = lib.mkEnableOption "GPU widget";
        intervalSeconds = lib.mkOption { type = t.ints.positive; default = 5; };
      };
      network = {
        enable = lib.mkOption { type = t.bool; default = true; };
      };
      battery = {
        enable = lib.mkOption { type = t.bool; default = true; };
      };
      workspaces = {
        enable = lib.mkOption { type = t.bool; default = true; };
      };
      sysmon = {
        enable = lib.mkOption { type = t.bool; default = true; };
      };
    };
  };
}
