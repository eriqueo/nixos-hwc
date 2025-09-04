# nixos-hwc/modules/home/hyprland/parts/session.nix
#
# Hyprland Session: Autostart Configuration & Session Management
# Charter v5 compliant - Universal session domain for lifecycle management
#
# DEPENDENCIES (Upstream):
#   - config.hwc.infrastructure.gpu.enable (for gpu-launch integration)
#   - systemPackages for basic tools (pkgs.jq, pkgs.procps, etc.)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let session = import ./parts/session.nix { inherit lib pkgs; };
#   in { exec-once = session.execOnce; }
#

{ lib, pkgs, ... }:
let
  # Dependencies for scripts
  inherit (pkgs) hyprland procps libnotify writeShellScriptBin jq coreutils gawk lm_sensors systemd;
in
{
  #============================================================================
  # AUTOSTART APPLICATIONS - Session initialization
  #============================================================================
  execOnce = [
    # "hyprland-startup"  # Disabled - was launching apps to specific workspaces
    "hyprpaper"           # Wallpaper manager
    "wl-paste --type text --watch cliphist store"    # Text clipboard history
    "wl-paste --type image --watch cliphist store"   # Image clipboard history
  ];

  #============================================================================
  # SESSION MANAGEMENT TOOLS
  #============================================================================
  tools = [
    # Session Startup Tool
    (writeShellScriptBin "hyprland-startup" ''
      #!/usr/bin/env bash
      # Hyprland session initialization with application auto-start
      set -euo pipefail

      # Function for logging
      log() {
        echo "[$(date '+%H:%M:%S')] $1" >> /tmp/hypr-startup.log
      }
      log "=== Hyprland Startup Begin ==="

      # Wait until Hyprland is fully ready with timeout
      TIMEOUT=30
      COUNTER=0
      until ${hyprland}/bin/hyprctl monitors > /dev/null 2>&1; do
        sleep 0.1
        COUNTER=$((COUNTER + 1))
        if [[ $COUNTER -gt $((TIMEOUT * 10)) ]]; then
          log "ERROR: Hyprland not ready after $TIMEOUT seconds"
          exit 1
        fi
      done

      log "Hyprland is ready"
      # Wait a bit more for full initialization
      sleep 1

      # Initialize GPU mode to Intel (default)
      echo "intel" > /tmp/gpu-mode
      log "GPU mode initialized to Intel"

      # Function to launch app with retry and better error handling
      launch_app() {
        local workspace=$1
        local command=$2
        local app_name=$3
        local delay=$4

        log "Launching $app_name on workspace $workspace"

        # Check if app is already running
        if ${procps}/bin/pgrep -f "$app_name" > /dev/null; then
          log "$app_name already running, skipping"
          return 0
        fi

        # Launch with error handling
        if ${hyprland}/bin/hyprctl dispatch exec "[workspace $workspace silent] $command"; then
          log "$app_name launch command sent successfully"
        else
          log "ERROR: Failed to launch $app_name"
        fi

        # Wait before next launch
        sleep "$delay"
      }

      # Function to check if workspace exists and create if needed
      ensure_workspace() {
        local workspace=$1
        if ! ${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -e ".[] | select(.id==$workspace)" > /dev/null 2>&1; then
          ${hyprland}/bin/hyprctl dispatch workspace "$workspace"
          sleep 0.2
          log "Created workspace $workspace"
        fi
      }

      # Pre-create workspaces to avoid race conditions
      for ws in {1..8}; do
        ensure_workspace "$ws"
      done

      log "Starting application launches..."

      # Launch applications with staggered timing for smoother startup
      launch_app 1 "waybar-gpu-launch thunar" "thunar" 0.8
      launch_app 2 "waybar-gpu-launch chromium" "chromium" 0.8
      launch_app 3 "waybar-gpu-launch chromium --new-window https://jobtread.com" "chromium" 0.8
      launch_app 4 "waybar-gpu-launch electron-mail" "electron-mail" 0.8
      launch_app 5 "waybar-gpu-launch obsidian" "obsidian" 0.8
      launch_app 6 "kitty -e nvim" "nvim" 0.8
      launch_app 7 "kitty" "kitty" 0.8
      launch_app 8 "kitty -e btop" "btop" 0.8

      # Wait for applications to settle
      sleep 2

      # Switch to workspace 1 with smooth transition
      log "Switching to workspace 1"
      ${hyprland}/bin/hyprctl dispatch workspace 1

      # Optional: Focus the first window in workspace 1
      sleep 0.5
      if ${hyprland}/bin/hyprctl clients -j | ${jq}/bin/jq -e '.[] | select(.workspace.id==1)' > /dev/null 2>&1; then
        ${hyprland}/bin/hyprctl dispatch focuswindow "$(${hyprland}/bin/hyprctl clients -j | ${jq}/bin/jq -r '.[] | select(.workspace.id==1) | .address' | head -1)"
        log "Focused first window in workspace 1"
      fi

      # Send notification that startup is complete
      ${libnotify}/bin/notify-send "Hyprland" "Startup complete! 🚀" -t 3000 -i desktop

      log "=== Hyprland Startup Complete ==="

      # Optional: Clean up old log files (keep last 5)
      find /tmp -name "hypr-startup.log.*" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true

      # Archive current log
      cp /tmp/hypr-startup.log "/tmp/hypr-startup.log.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    '')

    # System Health Checker Tool
    (writeShellScriptBin "hyprland-system-health-checker" ''
      #!/usr/bin/env bash
      # Check system health and show warnings
      set -euo pipefail

      # Check disk space
      DISK_USAGE=$(${coreutils}/bin/df / | ${gawk}/bin/awk 'NR==2 {print int($5)}' | sed 's/%//')
      if [[ $DISK_USAGE -gt 90 ]]; then
        ${libnotify}/bin/notify-send "System Warning" "Disk usage is at $DISK_USAGE%!" -u critical -i dialog-warning
      fi

      # Check memory usage
      MEM_USAGE=$(${procps}/bin/free | grep Mem | ${gawk}/bin/awk '{printf "%.0f", $3/$2 * 100.0}')
      if [[ $MEM_USAGE -gt 90 ]]; then
        ${libnotify}/bin/notify-send "System Warning" "Memory usage is at $MEM_USAGE%!" -u critical -i dialog-warning
      fi

      # Check CPU temperature
      TEMP=$(${lm_sensors}/bin/sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | ${gawk}/bin/awk '{print $3}' | sed 's/+//;s/°C.*//' | cut -d'.' -f1 || echo "0")
      if [[ $TEMP -gt 80 ]]; then
        ${libnotify}/bin/notify-send "System Warning" "CPU temperature is $TEMP°C!" -u critical -i dialog-warning
      fi

      # Check if waybar is running
      if ! ${procps}/bin/pgrep -f waybar > /dev/null; then
        ${libnotify}/bin/notify-send "System Info" "Waybar is not running, attempting restart..." -i dialog-information
        ${systemd}/bin/systemctl --user restart waybar
      fi
    '')
  ];
}