# domains/home/apps/hyprland/parts/scripts.nix
#
# HYPRLAND SCRIPTS - Window manager helper tools
# Pure script definitions for Hyprland session management
#
# DEPENDENCIES (Upstream):
#   - pkgs (Nixpkgs for writeShellScriptBin and tool dependencies)
#
# USED BY (Downstream):
#   - domains/home/apps/hyprland/sys.nix (imports and exposes as system packages)
#
# USAGE:
#   let scripts = import ./parts/scripts.nix { inherit pkgs lib; };
#   in { environment.systemPackages = scripts; }

{ pkgs, lib, ... }:

with pkgs;

[
  #============================================================================
  # WORKSPACE OVERVIEW - Enhanced workspace selector with window previews
  #============================================================================
  (writeShellScriptBin "hyprland-workspace-overview" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Get all workspaces with their contents
    WORKSPACES=$(${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -r '
      .[] |
      if .windows > 0 then
        "\(.id): \(.windows) windows - \(.lastwindowtitle // "empty")"
      else
        "\(.id): empty"
      end
    ' | sort -n)

    # Use wofi to select workspace
    SELECTED=$(echo "$WORKSPACES" | ${wofi}/bin/wofi --dmenu --prompt "Go to workspace:" --lines 10)

    if [[ -n "$SELECTED" ]]; then
      WORKSPACE_ID=$(echo "$SELECTED" | cut -d: -f1)
      ${hyprsome}/bin/hyprsome workspace "$WORKSPACE_ID"
      ${libnotify}/bin/notify-send "Workspace" "Switched to workspace $WORKSPACE_ID" -t 1000 -i desktop
    fi
  '')

  #============================================================================
  # MONITOR TOGGLE - Switch external monitor position (left/right)
  #============================================================================
  (writeShellScriptBin "hyprland-monitor-toggle" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Get list of connected monitors
    MONITORS=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r '.[].name')
    LAPTOP=$(echo "$MONITORS" | ${gnugrep}/bin/grep -E "(eDP|LVDS)" | head -1)
    EXTERNAL=$(echo "$MONITORS" | ${gnugrep}/bin/grep -v -E "(eDP|LVDS)" | head -1)

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
      ${hyprland}/bin/hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_SPEC,0x0,1"
      ${hyprland}/bin/hyprctl keyword monitor "$LAPTOP,$LAPTOP_SPEC,''${EXTERNAL_WIDTH}x0,1"
      ${libnotify}/bin/notify-send "Monitor" "External monitor moved to left" -t 2000 -i display
    else
      # Laptop is on right, move external to right
      ${hyprland}/bin/hyprctl keyword monitor "$LAPTOP,$LAPTOP_SPEC,0x0,1"
      ${hyprland}/bin/hyprctl keyword monitor "$EXTERNAL,$EXTERNAL_SPEC,''${LAPTOP_WIDTH}x0,1"
      ${libnotify}/bin/notify-send "Monitor" "External monitor moved to right" -t 2000 -i display
    fi
  '')

  #============================================================================
  # SYSTEM HEALTH CHECKER - Monitor disk, memory, CPU temp, and services
  #============================================================================
  (writeShellScriptBin "hyprland-system-health-checker" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Check disk space
    DISK_USAGE=$(${coreutils}/bin/df / | ${gawk}/bin/awk 'NR==2 {print int($5)}' | sed 's/%//')
    if [[ $DISK_USAGE -gt 90 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "Disk usage is at $DISK_USAGE%!" -u critical -i dialog-warning
    fi

    # Check memory usage
    MEM_USAGE=$(${procps}/bin/free | ${gnugrep}/bin/grep Mem | ${gawk}/bin/awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $MEM_USAGE -gt 90 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "Memory usage is at $MEM_USAGE%!" -u critical -i dialog-warning
    fi

    # Check CPU temperature
    TEMP=$(${lm_sensors}/bin/sensors 2>/dev/null | ${gnugrep}/bin/grep -E "(Core 0|Tctl)" | head -1 | ${gawk}/bin/awk '{print $3}' | sed 's/+//;s/°C.*//' | cut -d'.' -f1 || echo "0")
    if [[ $TEMP -gt 80 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "CPU temperature is $TEMP°C!" -u critical -i dialog-warning
    fi

    # Check if waybar is running
    if ! ${procps}/bin/pgrep -f waybar > /dev/null; then
      ${libnotify}/bin/notify-send "System Info" "Waybar is not running, attempting restart..." -i dialog-information
      ${systemd}/bin/systemctl --user restart waybar
    fi

    # If all checks pass, show success
    ${libnotify}/bin/notify-send "System Health" "All systems nominal ✓\nDisk: $DISK_USAGE% | Memory: $MEM_USAGE% | CPU: $TEMP°C" -t 3000 -i emblem-ok-symbolic
  '')
]
