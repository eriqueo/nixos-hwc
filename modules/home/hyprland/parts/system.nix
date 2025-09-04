# nixos-hwc/modules/home/hyprland/parts/system.nix
#
# Hyprland System Integration: Cross-Stream System Configuration
# Charter v6 compliant - Universal system domain for cross-stream integration
#
# DEPENDENCIES (Upstream):
#   - None (system integration)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#   - profiles/workstation.nix (system imports)
#
# USAGE:
#   let system = import ./parts/system.nix { inherit config lib pkgs; };
#   in {
#     environment.systemPackages = system.packages;
#     systemd.user.services = system.services;
#   }
#

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hyprlandTools;
  
  # Dependencies for all Hyprland tools
  inherit (pkgs) hyprland procps libnotify writeShellScriptBin jq coreutils gawk lm_sensors systemd;
in
{
  #============================================================================
  # OPTIONS - Infrastructure-level configuration for Hyprland Tools
  #============================================================================
  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Hyprland management tools for system-wide access";
    
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show notifications for tool actions";
    };
  };

  #============================================================================
  # IMPLEMENTATION - System packages and services
  #============================================================================  
  config = lib.mkIf cfg.enable {
    # System-wide Hyprland tools and packages (available to all contexts)
    environment.systemPackages = [
      # Core Hyprland ecosystem packages needed for keybindings
      hyprland  # Provides hyprctl
      pkgs.wofi
      pkgs.hyprshot
      pkgs.hypridle
      pkgs.hyprpaper
      pkgs.hyprlock
      pkgs.cliphist
      pkgs.wl-clipboard
      pkgs.brightnessctl
      pkgs.hyprsome
      
      # Management tools
      # Workspace Management Tools
      (writeShellScriptBin "hyprland-workspace-overview" ''
        #!/usr/bin/env bash
        # Quick workspace overview with application status
        set -euo pipefail

        # Get all workspaces with windows
        WORKSPACES=$(${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -r '.[] | select(.windows > 0) | "\(.id): \(.windows) windows"')
        
        # Get current workspace  
        CURRENT=$(${hyprland}/bin/hyprctl activeworkspace -j | ${jq}/bin/jq -r '.id')
        
        # Show overview
        echo "=== Workspace Overview ==="
        echo "Current: $CURRENT"
        echo ""
        echo "$WORKSPACES"
        
        # Get active window info
        ACTIVE_WINDOW=$(${hyprland}/bin/hyprctl activewindow -j | ${jq}/bin/jq -r '.class // "No active window"')
        echo ""
        echo "Active: $ACTIVE_WINDOW"
      '')

      # Workspace Manager Tool  
      (writeShellScriptBin "hyprland-workspace-manager" ''
        #!/usr/bin/env bash
        # Enhanced workspace navigation and management
        set -euo pipefail

        case "$1" in
          "overview")
            hyprland-workspace-overview
            ;;
          "next")
            ${hyprland}/bin/hyprctl dispatch workspace e+1
            ;;
          "prev")
            ${hyprland}/bin/hyprctl dispatch workspace e-1
            ;;
          *)
            echo "Usage: workspace-manager {overview|next|prev}"
            exit 1
            ;;
        esac
      '')


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
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "Monitor" "No external monitor detected" -t 2000 -i display
          ''}
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
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "Monitor" "External monitor moved to left" -t 2000 -i display
          ''}
        else
          # Laptop is on right, move external to right
          echo "Moving external monitor to right"
          ${hyprland}/bin/hyprctl keyword monitor "$LAPTOP,$LAPTOP_SPEC,0x0,1"
          ${hyprland}/bin/hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_SPEC,''${LAPTOP_WIDTH}x0,1"
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "Monitor" "External monitor moved to right" -t 2000 -i display
          ''}
        fi
      '')

      # System Health Checker Tool
      (writeShellScriptBin "hyprland-system-health-checker" ''
        #!/usr/bin/env bash
        # Check system health and show warnings
        set -euo pipefail

        # Check disk space
        DISK_USAGE=$(${coreutils}/bin/df / | ${gawk}/bin/awk 'NR==2 {print int($5)}' | sed 's/%//')
        if [[ $DISK_USAGE -gt 90 ]]; then
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "System Warning" "Disk usage is at $DISK_USAGE%!" -u critical -i dialog-warning
          ''}
        fi

        # Check memory usage
        MEM_USAGE=$(${procps}/bin/free | grep Mem | ${gawk}/bin/awk '{printf "%.0f", $3/$2 * 100.0}')
        if [[ $MEM_USAGE -gt 90 ]]; then
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "System Warning" "Memory usage is at $MEM_USAGE%!" -u critical -i dialog-warning
          ''}
        fi

        # Check CPU temperature
        TEMP=$(${lm_sensors}/bin/sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | ${gawk}/bin/awk '{print $3}' | sed 's/+//;s/°C.*//' | cut -d'.' -f1 || echo "0")
        if [[ $TEMP -gt 80 ]]; then
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "System Warning" "CPU temperature is $TEMP°C!" -u critical -i dialog-warning
          ''}
        fi

        # Check if waybar is running
        if ! ${procps}/bin/pgrep -f waybar > /dev/null; then
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "System Info" "Waybar is not running, attempting restart..." -i dialog-information
          ''}
          ${systemd}/bin/systemctl --user restart waybar
        fi
      '')
    ];
  };
}