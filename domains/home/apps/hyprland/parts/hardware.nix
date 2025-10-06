# HWC Charter Module/domains/home/hyprland/parts/hardware.nix
#
# Hyprland Hardware: Monitor Configuration, Input Settings & Display Management
# Charter v5 compliant - Universal hardware domain for physical device interaction
#
# DEPENDENCIES (Upstream):
#   - None (hardware configuration and control)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let hardware = import ./parts/hardware.nix { inherit lib pkgs; };
#   in { 
#     monitor = hardware.monitor;
#     workspace = hardware.workspace;
#     input = hardware.input;
#   }
#

{ lib, pkgs, ... }:
let
  # Dependencies for scripts
  inherit (pkgs) hyprland jq libnotify;
in
{
  #============================================================================
  # MONITOR CONFIGURATION - Exact monolith preservation
  #============================================================================
  monitor = [
    "eDP-1,2560x1600@165,0x0,1"      # Laptop at 0,0 (left)
    "DP-1,1920x1080@60,2560x0,1"     # External at 2560,0 (right)
  ];
  
  #============================================================================
  # WORKSPACE ASSIGNMENTS - Monitor-specific workspace mapping
  #============================================================================
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

  #============================================================================
  # INPUT CONFIGURATION - Keyboard and touchpad settings
  #============================================================================
  input = {
    kb_layout = "us";
    follow_mouse = 1;
    touchpad = {
      natural_scroll = true;
    };
  };

  # Tools moved to parts/system.nix for system-wide access
}