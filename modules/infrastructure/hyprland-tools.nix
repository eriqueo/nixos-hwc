# nixos-hwc/modules/infrastructure/hyprland-tools.nix
#
# HYPRLAND TOOLS - Complete window manager helper tools for Hyprland integration
# Provides all 6 session management and window manipulation tools
#
# DEPENDENCIES (Upstream):
#   - config.hwc.infrastructure.gpu.enable (for gpu-launch integration)
#   - systemPackages for basic tools (pkgs.jq, pkgs.wofi, etc.)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix (consumes all 6 tool binaries)
#   - profiles/workstation.nix (enables infrastructure capability)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/infrastructure/hyprland-tools.nix
#
# USAGE:
#   hwc.infrastructure.hyprlandTools.enable = true;
#   # Provides: all 6 tools with dual naming (hyprland-* + unprefixed wrappers)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.hyprlandTools;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Complete window manager tools for Hyprland";
    
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show desktop notifications for tool actions";
    };

    healthMonitoring = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable system health monitoring service";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    # Export all window manager tools to system packages
    environment.systemPackages = with pkgs; [
      #========================================================================
      # WORKSPACE MANAGEMENT TOOLS (2 tools)
      #========================================================================
      
      # 1. Workspace Overview
      (writeShellScriptBin "hyprland-workspace-overview" ''
        #!/usr/bin/env bash
        # Enhanced workspace overview with window previews
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
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "Workspace" "Switched to workspace $WORKSPACE_ID" -t 1000 -i desktop
          ''}
        fi
      '')

      # 2. Workspace Manager
      (writeShellScriptBin "hyprland-workspace-manager" ''
        #!/usr/bin/env bash
        # Enhanced workspace management with better UX
        set -euo pipefail
        
        case "$1" in
          "overview")
            # Show workspace overview with window counts and previews
            WORKSPACES=$(${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -r '
              .[] | 
              if .windows > 0 then
                "\(.id): \(.windows) windows - \(.lastwindowtitle // "empty")"
              else
                "\(.id): empty"
              end
            ' | sort -n)
            
            SELECTED=$(echo "$WORKSPACES" | ${wofi}/bin/wofi --dmenu --prompt "Go to workspace:" --lines 10 --width 600)
            
            if [[ -n "$SELECTED" ]]; then
              WORKSPACE_ID=$(echo "$SELECTED" | cut -d: -f1)
              ${hyprland}/bin/hyprctl dispatch workspace "$WORKSPACE_ID"
              ${lib.optionalString cfg.notifications ''
                ${libnotify}/bin/notify-send "Workspace" "Switched to workspace $WORKSPACE_ID" -t 1000 -i desktop
              ''}
            fi
            ;;
            
          "next")
            # Smart next workspace (skip empty ones or wrap around)
            CURRENT=$(${hyprland}/bin/hyprctl activewindow -j | ${jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")
            NEXT=$((CURRENT + 1))
            
            # Wrap around at 8
            if [[ $NEXT -gt 8 ]]; then
              NEXT=1
            fi
            
            ${hyprland}/bin/hyprctl dispatch workspace "$NEXT"
            ;;
            
          "prev")
            # Smart previous workspace
            CURRENT=$(${hyprland}/bin/hyprctl activewindow -j | ${jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")
            PREV=$((CURRENT - 1))
            
            # Wrap around at 1
            if [[ $PREV -lt 1 ]]; then
              PREV=8
            fi
            
            ${hyprland}/bin/hyprctl dispatch workspace "$PREV"
            ;;
            
          "move")
            # Move current window to specified workspace
            if [[ -n "$2" ]]; then
              ${hyprland}/bin/hyprctl dispatch movetoworkspace "$2"
              ${lib.optionalString cfg.notifications ''
                ${libnotify}/bin/notify-send "Window" "Moved to workspace $2" -t 1000 -i window
              ''}
            fi
            ;;
            
          *)
            echo "Usage: workspace-manager {overview|next|prev|move <workspace>}"
            exit 1
            ;;
        esac
      '')

      #========================================================================
      # MONITOR MANAGEMENT TOOLS (1 tool)
      #========================================================================
      
      # 3. Monitor Toggle
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

      #========================================================================
      # APPLICATION MANAGEMENT TOOLS (2 tools)
      #========================================================================
      
      # 4. Application Launcher  
      (writeShellScriptBin "hyprland-app-launcher" ''
        #!/usr/bin/env bash
        # Enhanced application launcher with workspace assignment
        set -euo pipefail
        
        case "$1" in
          "browser")
            if ${procps}/bin/pgrep -f chromium > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "chromium"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 2] waybar-gpu-launch chromium"
            fi
            ;;
            
          "files")
            if ${procps}/bin/pgrep -f thunar > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "thunar"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 1] waybar-gpu-launch thunar"
            fi
            ;;
            
          "terminal")
            ${hyprland}/bin/hyprctl dispatch exec "[workspace 7] kitty"
            ;;
            
          "editor")
            if ${procps}/bin/pgrep -f nvim > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "nvim"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 6] kitty -e nvim"
            fi
            ;;
            
          "email")
            if ${procps}/bin/pgrep -f electron-mail > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "electron-mail"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 4] waybar-gpu-launch electron-mail"
            fi
            ;;
            
          "notes")
            if ${procps}/bin/pgrep -f obsidian > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "obsidian"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 5] waybar-gpu-launch obsidian"
            fi
            ;;
            
          "monitor")
            if ${procps}/bin/pgrep -f btop > /dev/null; then
              ${hyprland}/bin/hyprctl dispatch focuswindow "btop"
            else
              ${hyprland}/bin/hyprctl dispatch exec "[workspace 8] kitty -e btop"
            fi
            ;;
            
          *)
            echo "Usage: app-launcher {browser|files|terminal|editor|email|notes|monitor}"
            exit 1
            ;;
        esac
      '')

      # 5. Session Startup
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
        ${lib.optionalString cfg.notifications ''
          ${libnotify}/bin/notify-send "Hyprland" "Startup complete! 🚀" -t 3000 -i desktop
        ''}
        
        log "=== Hyprland Startup Complete ==="
        
        # Optional: Clean up old log files (keep last 5)
        find /tmp -name "hypr-startup.log.*" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true
        
        # Archive current log
        cp /tmp/hypr-startup.log "/tmp/hypr-startup.log.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
      '')

      #========================================================================
      # SYSTEM MONITORING TOOLS (1 tool)  
      #========================================================================
      
      # 6. System Health Checker
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

    #==========================================================================
    # SYSTEM SERVICES - Health monitoring integration
    #==========================================================================
    systemd.user = lib.mkIf cfg.healthMonitoring {
      services.hyprland-system-health-checker = {
        Unit = {
          Description = "System health monitoring service";
          After = "graphical-session.target";
        };
        
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "system-health-checker-wrapper" ''
            exec /run/current-system/sw/bin/hyprland-system-health-checker
          ''}";
        };
        
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      # Timer for regular health checks
      timers.hyprland-system-health-checker = {
        Unit = {
          Description = "Run system health checker every 10 minutes";
          Requires = "hyprland-system-health-checker.service";
        };
        
        Timer = {
          OnCalendar = "*:0/10";
          Persistent = true;
        };
        
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}