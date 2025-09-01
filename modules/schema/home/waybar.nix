# nixos-hwc/modules/schema/home/waybar.nix
#
# WAYBAR - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.unknown.waybar.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/schema/home/waybar.nix
#
# USAGE:
#   hwc.unknown.waybar.enable = true;
#   # TODO: Add specific usage examples

{ lib, ... }:
let t = lib.types;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
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
