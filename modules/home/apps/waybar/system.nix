# nixos-hwc/modules/home/waybar/service.nix
#
# WAYBAR HARDWARE TOOLS - Complete hardware monitoring tools for Waybar integration
# This module defines the system-wide tools required by Waybar, now co-located within the
# Waybar module as per Charter v6's 5-file pattern for complex applications.
#
# DEPENDENCIES:
#   - pkgs.jq, pkgs.libnotify, etc. (defined within the module)
#
# USED BY:
#   - modules/home/waybar/default.nix (imports this module)
#   - profiles/workstation.nix (enables infrastructure capability via waybar.enable)
#
# USAGE:
#   Import this module in modules/home/waybar/default.nix.
#   Enable via programs.waybar.enable = true; (which implicitly enables this service)

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.waybar;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.programs.waybar.notifications = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Show desktop notifications for Waybar tool actions";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    # Export all hardware monitoring tools to system packages
    environment.systemPackages = with pkgs; [
      #========================================================================
      # GPU MANAGEMENT TOOLS (4 tools)
      #========================================================================
      
      # 1. GPU Status Monitor
      (writeShellScriptBin "waybar-gpu-status" ''
        #!/usr/bin/env bash
        # Check current GPU status and return JSON for waybar
        set -euo pipefail

        GPU_MODE_FILE="/tmp/gpu-mode"
        DEFAULT_MODE="intel"

        # Initialize mode file if it doesn't exist
        if [[ ! -f "$GPU_MODE_FILE" ]]; then
          echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
        fi

        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")

        # Get current GPU renderer with better detection
        CURRENT_GPU=$(${mesa-demos}/bin/glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")

        # Get GPU power consumption and temperature (if available)
        NVIDIA_POWER=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        NVIDIA_TEMP=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")

        case "$CURRENT_MODE" in
          "intel")
            ICON="󰢮"
            CLASS="intel"
            TOOLTIP="Intel Mode: $CURRENT_GPU"
            ;;
          "nvidia")
            ICON="󰾲"
            CLASS="nvidia"
            TOOLTIP="NVIDIA Mode: $CURRENT_GPU\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C"
            ;;
          "performance")
            ICON="⚡"
            CLASS="performance"
            TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C"
            ;;
          *)
            ICON="󰢮"
            CLASS="intel"
            TOOLTIP="Intel Mode (Default): $CURRENT_GPU"
            ;;
        esac

        # Output JSON for waybar
        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')

      # 2. GPU Toggle
      (writeShellScriptBin "waybar-gpu-toggle" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        GPU_MODE_FILE="/tmp/gpu-mode"
        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

        case "$CURRENT_MODE" in
          "intel")
            echo "performance" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''
              ${libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
            ''}
            ;;
          "performance")
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''
              ${libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
            ''}
            ;;
          *)
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''
              ${libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
            ''}
            ;;
        esac

        # Refresh waybar
        ${procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true
      ''))

      # 3. GPU Launch
      (writeShellScriptBin "waybar-gpu-launch" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if [[ $# -eq 0 ]]; then
          echo "Usage: gpu-launch <application> [args...]"
          exit 1
        fi

        GPU_MODE_FILE="/tmp/gpu-mode"
        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

        NEXT_NVIDIA_FILE="/tmp/gpu-next-nvidia"
        if [[ -f "$NEXT_NVIDIA_FILE" ]]; then
          rm "$NEXT_NVIDIA_FILE"
          exec nvidia-offload "$@"
        fi

        case "$CURRENT_MODE" in
          "performance")
            case "$1" in
              blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|librewolf)
                exec nvidia-offload "$@"
                ;;
              *)
                exec "$@"
                ;;
            esac
            ;;
          "nvidia")
            exec nvidia-offload "$@"
            ;;
          *)
            exec "$@"
            ;;
        esac
      ''))

      # 4. GPU Menu
      (writeShellScriptBin "waybar-gpu-menu" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        CHOICE=$(echo -e "Launch next app with NVIDIA\nView GPU usage\nOpen nvidia-settings\nToggle Performance Mode" | ${wofi}/bin/wofi --dmenu --prompt "GPU Options:")

        case "$CHOICE" in
          "Launch next app with NVIDIA")
            touch /tmp/gpu-next-nvidia
            ${lib.optionalString cfg.notifications ''
              ${libnotify}/bin/notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
            ''}
            ;;
          "View GPU usage")
            ${kitty}/bin/kitty --title "GPU Monitor" -e ${nvtopPackages.full}/bin/nvtop &
            ;;
          "Open nvidia-settings")
            nvidia-settings &
            ;;
          "Toggle Performance Mode")
            waybar-gpu-toggle
            ;;
        esac
      ''))

      #========================================================================
      # SYSTEM MONITORING TOOLS (4 tools)
      #========================================================================
      
      # 5. Workspace Switcher
      (writeShellScriptBin "waybar-workspace-switcher" ''
        #!/usr/bin/env bash
        # Enhanced workspace switching with visual feedback
        set -euo pipefail

        if [[ $# -eq 0 ]]; then
          echo "Usage: workspace-switcher <workspace_number>"
          exit 1
        fi

        WORKSPACE=$1

        # Get current workspace
        CURRENT=$(${hyprland}/bin/hyprctl activewindow -j | ${jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")

        if [[ "$CURRENT" != "$WORKSPACE" ]]; then
          # Switch workspace
          ${hyprland}/bin/hyprctl dispatch workspace "$WORKSPACE"

          # Show notification with workspace info
          WORKSPACE_INFO=$(${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -r ".[] | select(.id==$WORKSPACE) | \"Workspace $WORKSPACE: \(.windows) windows\"" 2>/dev/null || echo "Workspace $WORKSPACE")
          ${lib.optionalString cfg.notifications ''
            ${libnotify}/bin/notify-send "Workspace" "$WORKSPACE_INFO" -t 1000 -i desktop
          ''}
        fi
      ''))

      # 6. Resource Monitor
      (writeShellScriptBin "waybar-resource-monitor" ''
        #!/usr/bin/env bash
        # Monitor system resources
        set -euo pipefail

        # CPU usage
        CPU_USAGE=$(${procps}/bin/top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed '%us,//')
        CPU_NUM=$(echo "$CPU_USAGE" | cut -d'.' -f1 | grep -o '[0-9]*' || echo "0")

        # Memory usage
        MEM_INFO=$(${procps}/bin/free | grep Mem)
        MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
        MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
        MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))

        # Temperature
        TEMP=$(${lm_sensors}/bin/sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | awk '{print $3}' | sed 's/+//;s/°C.*//' || echo "0")
        TEMP_NUM=$(echo "$TEMP" | cut -d'.' -f1 | grep -o '[0-9]*' || echo "0")

        exit 0
      ''))

      # 7. Network Status  
      (writeShellScriptBin "waybar-network-status" ''
        #!/usr/bin/env bash
        # Enhanced network status with quality indicators
        set -euo pipefail

        # Get primary network connection (exclude loopback, VPN tunnels, and bridges)
        ACTIVE_CONN=$(${networkmanager}/bin/nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -v ":loopback:\|:tun:\|:bridge:" | head -1)

        if [[ -z "$ACTIVE_CONN" ]]; then
          echo "{\"text\": \"󰤭\", \"class\": \"disconnected\", \"tooltip\": \"No network connection\"}"
          exit 0
        fi

        CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
        CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
        DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)

        if [[ "$CONN_TYPE" == "802-11-wireless" ]]; then
          # Get WiFi signal strength
          SIGNAL=$(${networkmanager}/bin/nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')
          SPEED=$(${iw}/bin/iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")

          if [[ $SIGNAL -gt 75 ]]; then
            ICON="󰤨"
            CLASS="excellent"
          elif [[ $SIGNAL -gt 50 ]]; then
            ICON="󰤥"
            CLASS="good"
          elif [[ $SIGNAL -gt 25 ]]; then
            ICON="󰤢"
            CLASS="fair"
          else
            ICON="󰤟"
            CLASS="poor"
          fi

          TOOLTIP="WiFi: $CONN_NAME\nSignal: $SIGNAL%\nSpeed: $SPEED"
        else
          ICON="󰈀"
          CLASS="ethernet"
          SPEED=$(${ethtool}/bin/ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
          TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
        fi

        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      ''))

      # 8. Battery Health
      (writeShellScriptBin "waybar-battery-health" ''
        #!/usr/bin/env bash
        set -euo pipefail

        BATTERY_PATH="/sys/class/power_supply/BAT0"

        if [[ ! -d "$BATTERY_PATH" ]]; then
          echo "{\"text\": \"󰂑\", \"tooltip\": \"No battery detected\"}"
          exit 0
        fi

        CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
        STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
        HEALTH=$(cat "$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
        CYCLE_COUNT=$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")

        # Calculate time remaining
        if [[ "$STATUS" == "Discharging" ]]; then
          POWER_NOW=$(cat "$BATTERY_PATH/power_now" 2>/dev/null || echo "0")
          ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now" 2>/dev/null || echo "0")

          if [[ $POWER_NOW -gt 0 ]]; then
            TIME_REMAINING=$(( ENERGY_NOW / POWER_NOW ))
            HOURS=$(( TIME_REMAINING ))
            MINUTES=$(( (TIME_REMAINING * 60) % 60 ))
            TIME_STR=$(printf '%sh %sm' "$HOURS" "$MINUTES")
          else
            TIME_STR="Unknown"
          fi
        else
          TIME_STR="N/A"
        fi

        # Choose icon based on capacity and status
        if [[ "$STATUS" == "Charging" ]]; then
          ICON="󰂄"
          CLASS="charging"
        elif [[ $CAPACITY -gt 90 ]]; then
          ICON="󰁹"
          CLASS="full"
        elif [[ $CAPACITY -gt 75 ]]; then
          ICON="󰂂"
          CLASS="high"
        elif [[ $CAPACITY -gt 50 ]]; then
          ICON="󰁿"
          CLASS="medium"
        elif [[ $CAPACITY -gt 25 ]]; then
          ICON="󰁼"
          CLASS="low"
        else
          ICON="󰁺"
          CLASS="critical"
        fi

        TOOLTIP="Battery: $CAPACITY%\nStatus: $STATUS\nHealth: $HEALTH\nCycles: $CYCLE_COUNT\nTime: $TIME_STR"

        echo "{\"text\": \"$ICON $CAPACITY%\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      ''))

      #========================================================================
      # SYSTEM CONTROL TOOLS (5 tools)
      #========================================================================
      
      # 9. Disk Usage GUI
      (writeShellScriptBin "waybar-disk-usage-gui" ''
        #!/usr/bin/env bash
        set -euo pipefail
        ${baobab}/bin/baobab &
      ''))

      # 10. System Monitor
      (writeShellScriptBin "waybar-system-monitor" ''
        #!/usr/bin/env bash
        set -euo pipefail
        ${kitty}/bin/kitty --title "System Monitor" -e ${btop}/bin/btop &
      ''))

      # 11. Network Settings
      (writeShellScriptBin "waybar-network-settings" ''
        #!/usr/bin/env bash
        # Comprehensive network management menu
        set -euo pipefail

        CHOICE=$(echo -e "WiFi Manager (nmtui)\nNetwork Connections Editor\nVPN Status\nNetwork Speed Test\nNetwork Diagnostics" | ${wofi}/bin/wofi --dmenu --prompt "Network Tools:")

        case "$CHOICE" in
          "WiFi Manager (nmtui)")
            ${kitty}/bin/kitty --title "WiFi Manager" -e ${networkmanager}/bin/nmtui &
            ;;
          "Network Connections Editor")
            ${networkmanagerapplet}/bin/nm-connection-editor &
            ;;
          "VPN Status")
            ${kitty}/bin/kitty --title "VPN Status" -e sh -c 'echo "=== VPN Status ==="; echo ""; vpnstatus; echo ""; echo "Commands: vpnon (connect) | vpnoff (disconnect)"; echo ""; read -p "Press Enter to close..."' &
            ;;
          "Network Speed Test")
            ${kitty}/bin/kitty --title "Network Speed Test" -e sh -c '${speedtest-cli}/bin/speedtest-cli; read -p "Press Enter to close..."' &
            ;;
          "Network Diagnostics")
            ${kitty}/bin/kitty --title "Network Diagnostics" -e sh -c 'echo "=== Network Diagnostics ==="; echo ""; echo "Current IP:"; ${curl}/bin/curl -s ifconfig.me; echo ""; echo ""; echo "Active Connections:"; ${networkmanager}/bin/nmcli connection show --active; echo ""; echo "WiFi Networks:"; ${networkmanager}/bin/nmcli dev wifi; echo ""; read -p "Press Enter to close..."' &
            ;;
        esac
      ''))

      # 12. Power Settings
      (writeShellScriptBin "waybar-power-settings" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if command -v gnome-power-statistics >/dev/null 2>&1; then
          gnome-power-statistics &
        elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
          xfce4-power-manager-settings &
        else
          ${kitty}/bin/kitty --title "Power Info" -e sh -c "${acpi}/bin/acpi -V && ${powertop}/bin/powertop --dump && read" &
        fi
      ''))

      # 13. Sensor Viewer
      (writeShellScriptBin "waybar-sensor-viewer" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if command -v mission-center >/dev/null 2>&1; then
          mission-center &
        else
          ${kitty}/bin/kitty --title "Sensors" -e sh -c "${lm_sensors}/bin/sensors && read" &
        fi
      ''))
    ];
  };
}

