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

{ pkgs, lib, osConfig ? {}, ... }:

with pkgs;

[
  #============================================================================
  # SMART WINDOW MOVE - Move within workspace, cross monitors at edges
  #============================================================================
  (writeShellScriptBin "hyprland-smart-move" ''
    #!/usr/bin/env bash
    set -euo pipefail

    DIRECTION="''${1:-r}"  # l, r, u, d

    # Get window position before move
    BEFORE=$(${hyprland}/bin/hyprctl activewindow -j)
    POS_BEFORE=$(echo "$BEFORE" | ${jq}/bin/jq -r '"\(.at[0]),\(.at[1])"')

    # Try to move within workspace
    ${hyprland}/bin/hyprctl dispatch movewindow "$DIRECTION"

    # Small delay for Hyprland to process
    sleep 0.05

    # Get window position after move
    AFTER=$(${hyprland}/bin/hyprctl activewindow -j)
    POS_AFTER=$(echo "$AFTER" | ${jq}/bin/jq -r '"\(.at[0]),\(.at[1])"')

    # If position unchanged, window was at edge - move to adjacent monitor
    if [[ "$POS_BEFORE" == "$POS_AFTER" ]]; then
      case "$DIRECTION" in
        l) ${hyprland}/bin/hyprctl dispatch movewindow mon:-1 ;;
        r) ${hyprland}/bin/hyprctl dispatch movewindow mon:+1 ;;
        u) ${hyprland}/bin/hyprctl dispatch movewindow mon:-1 ;;
        d) ${hyprland}/bin/hyprctl dispatch movewindow mon:+1 ;;
      esac
    fi
  '')

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

    # Get monitor data once
    MONITOR_DATA=$(${hyprland}/bin/hyprctl monitors -j)

    # Identify laptop and external monitors
    LAPTOP=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r '.[] | select(.name | test("eDP|LVDS")) | .name' | head -1)
    EXTERNAL=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r '.[] | select(.name | test("eDP|LVDS") | not) | .name' | head -1)

    if [[ -z "$EXTERNAL" ]]; then
      ${libnotify}/bin/notify-send "Monitor" "No external monitor detected" -t 2000 -i display
      exit 1
    fi

    # Get current laptop position
    LAPTOP_POS=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | .x")

    # Get monitor specs (resolution@refresh,position,scale)
    LAPTOP_SPEC=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | \"\(.width)x\(.height)@\(.refreshRate | floor)\"")
    EXTERNAL_SPEC=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | \"\(.width)x\(.height)@\(.refreshRate | floor)\"")
    LAPTOP_SCALE=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | .scale")
    EXTERNAL_SCALE=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | .scale")

    # Calculate effective widths (accounting for scale)
    LAPTOP_WIDTH=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | (.width / .scale | floor)")
    EXTERNAL_WIDTH=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | (.width / .scale | floor)")

    if [[ $LAPTOP_POS -eq 0 ]]; then
      # Laptop is on left, move external to left (use --batch for atomic change)
      ${hyprland}/bin/hyprctl --batch "keyword monitor $EXTERNAL,$EXTERNAL_SPEC,0x0,$EXTERNAL_SCALE ; keyword monitor $LAPTOP,$LAPTOP_SPEC,''${EXTERNAL_WIDTH}x0,$LAPTOP_SCALE"
      ${libnotify}/bin/notify-send "Monitor" "External on left" -t 1500 -i display
    else
      # Laptop is on right, move external to right
      ${hyprland}/bin/hyprctl --batch "keyword monitor $LAPTOP,$LAPTOP_SPEC,0x0,$LAPTOP_SCALE ; keyword monitor $EXTERNAL,$EXTERNAL_SPEC,''${LAPTOP_WIDTH}x0,$EXTERNAL_SCALE"
      ${libnotify}/bin/notify-send "Monitor" "External on right" -t 1500 -i display
    fi

    # Restart waybar to pick up monitor changes
    ${systemd}/bin/systemctl --user restart waybar
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

  #============================================================================
  # KEYBINDS VIEWER - Display all Hyprland keybindings in searchable wofi
  #============================================================================
  (writeShellScriptBin "hyprland-keybinds-viewer" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Get keybinds as JSON and format for display
    KEYBINDS=$(${hyprland}/bin/hyprctl binds -j | ${jq}/bin/jq -r '
      .[] |
      .modmask as $m |
      # Build modifier string from bitmask
      (
        [
          (if ($m % 2) == 1 then "SHIFT" else empty end),
          (if (($m / 4 | floor) % 2) == 1 then "CTRL" else empty end),
          (if (($m / 8 | floor) % 2) == 1 then "ALT" else empty end),
          (if (($m / 64 | floor) % 2) == 1 then "SUPER" else empty end)
        ] | join("+")
      ) as $mods |
      (if ($mods | length) > 0 then $mods + "+" else "" end) +
      .key +
      " -> " +
      .dispatcher +
      (if (.arg | length) > 0 then " " + .arg else "" end)
    ' | sort)

    # Display in wofi
    echo "$KEYBINDS" | ${wofi}/bin/wofi --dmenu --prompt "Keybindings:" --lines 20 --width 600
  '')
]