#-----------------------------------------------------------------------------
# FILE : modules/home-manager/ui/startup.nix (SESSION STARTUP) - ENHANCED
# -----------------------------------------------------------------------------
{ config, pkgs, lib, ... }:

let
  hyprStartup = pkgs.writeScriptBin "hypr-startup" ''
    #!/usr/bin/env bash    
    # Function for logging
    log() {
      echo "[$(date '+%H:%M:%S')] $1" >> /tmp/hypr-startup.log
    }
    log "=== Hyprland Startup Begin ==="
    
    # Wait until Hyprland is fully ready with timeout
    TIMEOUT=30
    COUNTER=0
    until hyprctl monitors > /dev/null 2>&1; do
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
      if pgrep -f "$app_name" > /dev/null; then
        log "$app_name already running, skipping"
        return 0
      fi
      
      # Launch with error handling
      if hyprctl dispatch exec "[workspace $workspace silent] $command"; then
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
      if ! hyprctl workspaces -j | ${pkgs.jq}/bin/jq -e ".[] | select(.id==$workspace)" > /dev/null 2>&1; then
        hyprctl dispatch workspace "$workspace"
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
    launch_app 1 "gpu-launch thunar" "thunar" 0.8
    launch_app 2 "gpu-launch chromium" "chromium" 0.8  
    launch_app 3 "gpu-launch chromium --new-window https://jobtread.com" "chromium" 0.8
    launch_app 4 "gpu-launch electron-mail" "electron-mail" 0.8
    launch_app 5 "gpu-launch obsidian" "obsidian" 0.8
    launch_app 6 "kitty -e nvim" "nvim" 0.8
    launch_app 7 "kitty" "kitty" 0.8
    launch_app 8 "kitty -e btop" "btop" 0.8
    
    # Wait for applications to settle
    sleep 2
    
    # Switch to workspace 1 with smooth transition
    log "Switching to workspace 1"
    hyprctl dispatch workspace 1
    
    # Optional: Focus the first window in workspace 1
    sleep 0.5
    if hyprctl clients -j | ${pkgs.jq}/bin/jq -e '.[] | select(.workspace.id==1)' > /dev/null 2>&1; then
      hyprctl dispatch focuswindow "$(hyprctl clients -j | ${pkgs.jq}/bin/jq -r '.[] | select(.workspace.id==1) | .address' | head -1)"
      log "Focused first window in workspace 1"
    fi
    
    # Send notification that startup is complete
    ${pkgs.libnotify}/bin/notify-send "Hyprland" "Startup complete! 🚀" -t 3000 -i desktop
    
    log "=== Hyprland Startup Complete ==="
    
    # Optional: Clean up old log files (keep last 5)
    find /tmp -name "hypr-startup.log.*" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true
    
    # Archive current log
    cp /tmp/hypr-startup.log "/tmp/hypr-startup.log.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  '';

  # Enhanced workspace management script
  workspaceManager = pkgs.writeScriptBin "workspace-manager" ''
    #!/usr/bin/env bash
    # Enhanced workspace management with better UX
    
    case "$1" in
      "overview")
        # Show workspace overview with window counts and previews
        WORKSPACES=$(hyprctl workspaces -j | ${pkgs.jq}/bin/jq -r '
          .[] | 
          if .windows > 0 then
            "\(.id): \(.windows) windows - \(.lastwindowtitle // "empty")"
          else
            "\(.id): empty"
          end
        ' | sort -n)
        
        SELECTED=$(echo "$WORKSPACES" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "Go to workspace:" --lines 10 --width 600)
        
        if [[ -n "$SELECTED" ]]; then
          WORKSPACE_ID=$(echo "$SELECTED" | cut -d: -f1)
          hyprctl dispatch workspace "$WORKSPACE_ID"
          ${pkgs.libnotify}/bin/notify-send "Workspace" "Switched to workspace $WORKSPACE_ID" -t 1000 -i desktop
        fi
        ;;
        
      "next")
        # Smart next workspace (skip empty ones or wrap around)
        CURRENT=$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")
        NEXT=$((CURRENT + 1))
        
        # Wrap around at 8
        if [[ $NEXT -gt 8 ]]; then
          NEXT=1
        fi
        
        hyprctl dispatch workspace "$NEXT"
        ;;
        
      "prev")
        # Smart previous workspace
        CURRENT=$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")
        PREV=$((CURRENT - 1))
        
        # Wrap around at 1
        if [[ $PREV -lt 1 ]]; then
          PREV=8
        fi
        
        hyprctl dispatch workspace "$PREV"
        ;;
        
      "move")
        # Move current window to specified workspace
        if [[ -n "$2" ]]; then
          hyprctl dispatch movetoworkspace "$2"
          ${pkgs.libnotify}/bin/notify-send "Window" "Moved to workspace $2" -t 1000 -i window
        fi
        ;;
        
      *)
        echo "Usage: workspace-manager {overview|next|prev|move <workspace>}"
        exit 1
        ;;
    esac
  '';

  # Application launcher with better integration
  appLauncher = pkgs.writeScriptBin "app-launcher" ''
    #!/usr/bin/env bash
    # Enhanced application launcher with workspace assignment
    
    case "$1" in
      "browser")
        if pgrep -f chromium > /dev/null; then
          hyprctl dispatch focuswindow "chromium"
        else
          hyprctl dispatch exec "[workspace 2] gpu-launch chromium"
        fi
        ;;
        
      "files")
        if pgrep -f thunar > /dev/null; then
          hyprctl dispatch focuswindow "thunar"
        else
          hyprctl dispatch exec "[workspace 1] gpu-launch thunar"
        fi
        ;;
        
      "terminal")
        hyprctl dispatch exec "[workspace 7] kitty"
        ;;
        
      "editor")
        if pgrep -f nvim > /dev/null; then
          hyprctl dispatch focuswindow "nvim"
        else
          hyprctl dispatch exec "[workspace 6] kitty -e nvim"
        fi
        ;;
        
      "email")
        if pgrep -f electron-mail > /dev/null; then
          hyprctl dispatch focuswindow "electron-mail"
        else
          hyprctl dispatch exec "[workspace 4] gpu-launch electron-mail"
        fi
        ;;
        
      "notes")
        if pgrep -f obsidian > /dev/null; then
          hyprctl dispatch focuswindow "obsidian"
        else
          hyprctl dispatch exec "[workspace 5] gpu-launch obsidian"
        fi
        ;;
        
      "monitor")
        if pgrep -f btop > /dev/null; then
          hyprctl dispatch focuswindow "btop"
        else
          hyprctl dispatch exec "[workspace 8] kitty -e btop"
        fi
        ;;
        
      *)
        echo "Usage: app-launcher {browser|files|terminal|editor|email|notes|monitor}"
        exit 1
        ;;
    esac
  '';

  # System health checker
  systemHealthChecker = pkgs.writeScriptBin "system-health-checker" ''
    #!/usr/bin/env bash
    # Check system health and show warnings
    
    # Check disk space
    DISK_USAGE=$(df / | awk 'NR==2 {print int($5)}' | sed 's/%//')
    if [[ $DISK_USAGE -gt 90 ]]; then
      ${pkgs.libnotify}/bin/notify-send "System Warning" "Disk usage is at $DISK_USAGE%!" -u critical -i dialog-warning
    fi
    
    # Check memory usage
    MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $MEM_USAGE -gt 90 ]]; then
      ${pkgs.libnotify}/bin/notify-send "System Warning" "Memory usage is at $MEM_USAGE%!" -u critical -i dialog-warning
    fi
    
    # Check CPU temperature
    TEMP=$(sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | awk '{print $3}' | sed 's/+//;s/°C.*//' | cut -d'.' -f1 || echo "0")
    if [[ $TEMP -gt 80 ]]; then
      ${pkgs.libnotify}/bin/notify-send "System Warning" "CPU temperature is $TEMP°C!" -u critical -i dialog-warning
    fi
    
    # Check if waybar is running
    if ! pgrep -f waybar > /dev/null; then
      ${pkgs.libnotify}/bin/notify-send "System Info" "Waybar is not running, attempting restart..." -i dialog-information
      systemctl --user restart waybar
    fi
  '';

in
{
  # Install enhanced startup scripts
  home.packages = [ 
    hyprStartup 
    workspaceManager
    appLauncher
    systemHealthChecker
    pkgs.libnotify  # For notifications
  ];
  
  # Create systemd service for system health monitoring
  systemd.user.services.system-health-checker = {
    Unit = {
      Description = "System health monitoring service";
      After = "graphical-session.target";
    };
    
    Service = {
      Type = "oneshot";
      ExecStart = "${systemHealthChecker}/bin/system-health-checker";
    };
    
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Timer for regular health checks
  systemd.user.timers.system-health-checker = {
    Unit = {
      Description = "Run system health checker every 10 minutes";
      Requires = "system-health-checker.service";
    };
    
    Timer = {
      OnCalendar = "*:0/10";
      Persistent = true;
    };
    
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}

