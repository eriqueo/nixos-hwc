# nixos-hwc/modules/home/hyprland/parts/hardware.nix
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
  inherit (pkgs) hyprland jq libnotify writeShellScriptBin;
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

  #============================================================================
  # HARDWARE MANAGEMENT TOOLS
  #============================================================================
  tools = [
    # Monitor Toggle Tool
    (writeShellScriptBin "hyprland-monitor-toggle" ''
      #!/usr/bin/env bash
      # Enhanced monitor layout switching
      set -euo pipefail

      # Get list of connected monitors
      MONITORS=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r '.[].name')
      LAPTOP=$(echo "$MONITORS" | grep -E "(eDP|LVDS)" | head -1)
      EXTERNAL=$(echo "$MONITORS" | grep -v -E "(eDP|LVDS)" | head -1)

      if [[ -z "$EXTERNAL" ]]; then
          ${libnotify}/bin/notify-send "Monitor" "No external monitor detected" -t 2000 -i display
          exit 1
      fi

      # Get current positions
      LAPTOP_POS=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | .x")
      EXTERNAL_POS=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | .x")

      # Get monitor specs
      LAPTOP_SPEC=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | \"\(.width)x\(.height)@\(.refreshRate)\"")
      EXTERNAL_SPEC=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | \"\(.width)x\(.height)@\(.refreshRate)\"")
      LAPTOP_WIDTH=$(echo "$LAPTOP_SPEC" | cut -d'x' -f1)
      EXTERNAL_WIDTH=$(echo "$EXTERNAL_SPEC" | cut -d'x' -f1)

      if [[ $LAPTOP_POS -eq 0 ]]; then
          # Laptop is on left, move external to left
          echo "Moving external monitor to left"
          ${hyprland}/bin/hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_SPEC,0x0,1"
          ${hyprland}/bin/hyprctl keyword monitor "$LAPTOP,$LAPTOP_SPEC,''${EXTERNAL_WIDTH}x0,1"
          ${libnotify}/bin/notify-send "Monitor" "External monitor moved to left" -t 2000 -i display
      else
          # Laptop is on right, move external to right
          echo "Moving external monitor to right"
          ${hyprland}/bin/hyprctl keyword monitor "$LAPTOP,$LAPTOP_SPEC,0x0,1"
          ${hyprland}/bin/hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_SPEC,''${LAPTOP_WIDTH}x0,1"
          ${libnotify}/bin/notify-send "Monitor" "External monitor moved to right" -t 2000 -i display
      fi
    '')
  ];
}