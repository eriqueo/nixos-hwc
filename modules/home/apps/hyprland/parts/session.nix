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
  inherit (pkgs) hyprland procps libnotify jq coreutils gawk lm_sensors systemd;
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "hyprctl setcursor Adwaita 24"
    ];
    env = [
      "XCURSOR_THEME,Adwaita"
      "XCURSOR_SIZE,24"
    ];
  };
  
  # Startup script for launching applications to specific workspaces
  hyprlandStartupScript = pkgs.writeScriptBin "hyprland-startup" ''
    #!/usr/bin/env bash    
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
    log "Setting initial GPU mode to Intel"
    
    # Launch applications to specific workspaces
    log "Launching workspace applications..."
    
    # Workspace 1: Terminal
    log "Launching kitty on workspace 1"
    ${hyprland}/bin/hyprctl dispatch workspace 1
    ${pkgs.kitty}/bin/kitty &
    sleep 0.5
    
    # Workspace 2: Browser (if available) 
    if command -v firefox > /dev/null 2>&1; then
      log "Launching Firefox on workspace 2"
      ${hyprland}/bin/hyprctl dispatch workspace 2
      firefox &
      sleep 0.5
    fi
    
    # Workspace 3: File Manager
    log "Launching Thunar on workspace 3"
    ${hyprland}/bin/hyprctl dispatch workspace 3
    ${pkgs.xfce.thunar}/bin/thunar &
    sleep 0.5
    
    # Return to workspace 1
    ${hyprland}/bin/hyprctl dispatch workspace 1
    
    log "=== Hyprland Startup Complete ==="
  '';
in
{
  #============================================================================
  # AUTOSTART APPLICATIONS - Session initialization
  #============================================================================
  execOnce = [
    "hyprland-startup"  # Launch applications to specific workspaces
    "hyprpaper"         # Wallpaper manager
    "waybar"            # Status bar
    "wl-paste --type text --watch cliphist store"    # Text clipboard history
    "wl-paste --type image --watch cliphist store"   # Image clipboard history
  ];
  
  #============================================================================
  # STARTUP SCRIPT PACKAGE - Make available to system PATH
  #============================================================================
  startupScript = hyprlandStartupScript;
  
  # Package to be included in home.packages
  packages = [ hyprlandStartupScript ];
}
