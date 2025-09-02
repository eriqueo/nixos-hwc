# nixos-hwc/modules/home/hyprland/parts/monitors.nix
#
# Hyprland Monitor Configuration: Exact Monolith Preservation
# Charter v4 compliant - Pure data for monitor and workspace layout
#
# DEPENDENCIES (Upstream):
#   - None (hardware configuration)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let mon = import ./parts/monitors.nix { inherit lib pkgs; };
#   in { monitor = mon.monitor; workspace = mon.workspace; }
#

{ lib, pkgs, ... }:
{
  # Monitor setup - exact preservation from monolith
  monitor = [
    "eDP-1,2560x1600@165,0x0,1"      # Laptop at 0,0 (left)
    "DP-1,1920x1080@60,2560x0,1"     # External at 2560,0 (right)
  ];
  
  # Workspace assignments - exact preservation from monolith
  workspace = [
    # Monitor ID 0 (eDP-1) gets workspaces 1-8
    "1,monitor:eDP-1"
    "2,monitor:eDP-1"
    "3,monitor:eDP-1"
    "4,monitor:eDP-1"
    "5,monitor:eDP-1"
    "6,monitor:eDP-1"
    "7,monitor:eDP-1"
    "8,monitor:eDP-1"
    
    # Monitor ID 1 (DP-1) gets workspaces 11-18
    "11,monitor:DP-1"
    "12,monitor:DP-1"
    "13,monitor:DP-1"
    "14,monitor:DP-1"
    "15,monitor:DP-1"
    "16,monitor:DP-1"
    "17,monitor:DP-1"
    "18,monitor:DP-1"
  ];
}