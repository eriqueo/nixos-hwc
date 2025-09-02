# nixos-hwc/modules/home/hyprland/parts/autostart.nix
#
# Hyprland Autostart Configuration: Session Initialization
# Charter v4 compliant - Pure data for exec-once commands
#
# DEPENDENCIES (Upstream):
#   - modules/infrastructure/hyprland-tools.nix (hyprland-startup)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let auto = import ./parts/autostart.nix { inherit lib pkgs; };
#   in { exec-once = auto.execOnce; }
#

{ lib, pkgs, ... }:
{
  execOnce = [
    "hyprland-startup"    # Calls infrastructure tool (replaces hypr-startup)
    "hyprpaper"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"
  ];
}