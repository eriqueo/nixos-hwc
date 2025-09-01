# nixos-hwc/modules/infrastructure/waybar-system-tools.nix
#
# WAYBAR SYSTEM TOOLS - System monitoring tools for Waybar integration
# Provides hardware monitoring scripts (network, battery, etc.) that waybar tools can consume
#
# DEPENDENCIES (Upstream):
#   - NetworkManager (for network status)
#   - Power supply sysfs (for battery monitoring)
#
# USED BY (Downstream):
#   - modules/home/waybar/tools/ (consume waybar-network-status, waybar-battery-health binaries)
#   - profiles/workstation.nix (enables infrastructure capability)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/infrastructure/waybar-system-tools.nix
#
# USAGE:
#   hwc.infrastructure.waybarSystemTools.enable = true;
#   # Provides: waybar-network-status, waybar-battery-health, waybar-gpu-menu binaries

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.waybarSystemTools;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.infrastructure.waybarSystemTools = {
    enable = lib.mkEnableOption "System monitoring tools for Waybar";
    
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable desktop notifications from system tools";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Export system monitoring tools to system packages
    environment.systemPackages = with pkgs; [
      # Network status monitoring
      (pkgs.writeShellScriptBin "waybar-network-status" ''
        #!/usr/bin/env bash
        set -euo pipefail

        ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | head -1 || true)
        if [[ -z "$ACTIVE_CONN" ]]; then
          echo '{"text":"󰤭","class":"disconnected","tooltip":"No network connection"}'
          exit 0
        fi

        CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
        CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
        DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)

        if [[ "$CONN_TYPE" == "wifi" ]]; then
          SIGNAL=$(nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}' || echo "0")
          SPEED=$(iw dev "$DEVICE" link 2>/dev/null | awk '/tx bitrate/ {print $3 " " $4}' || echo "Unknown")
          if [[ ''${SIGNAL:-0} -gt 75 ]]; then ICON="󰤨"; CLASS="excellent"
          elif [[ ''${SIGNAL:-0} -gt 50 ]]; then ICON="󰤥"; CLASS="good"
          elif [[ ''${SIGNAL:-0} -gt 25 ]]; then ICON="󰤢"; CLASS="fair"
          else ICON="󰤟"; CLASS="poor"; fi
          TOOLTIP="WiFi: $CONN_NAME\\nSignal: $SIGNAL%\\nSpeed: $SPEED"
        else
          ICON="󰈀"; CLASS="ethernet"
          SPEED=$(ethtool "$DEVICE" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' || echo "Unknown")
          TOOLTIP="Ethernet: $CONN_NAME\\nSpeed: $SPEED"
        fi

        printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$ICON" "$CLASS" "$TOOLTIP"
      '')

      # Battery health monitoring  
      (pkgs.writeShellScriptBin "waybar-battery-health" ''
        #!/usr/bin/env bash
        set -euo pipefail

        BATTERY_PATH="/sys/class/power_supply/BAT0"
        CAPACITY="0"; STATUS="Unknown"; HEALTH="Unknown"; CYCLE_COUNT="Unknown"

        if [[ -d "$BATTERY_PATH" ]]; then
          CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
          STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
          HEALTH=$(cat "$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
          CYCLE_COUNT=$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")
        fi

        if [[ "$STATUS" == "Charging" ]]; then ICON="󰂄"; CLASS="charging"
        elif [[ ''${CAPACITY:-0} -gt 90 ]]; then ICON="󰁹"; CLASS="full"
        elif [[ ''${CAPACITY:-0} -gt 75 ]]; then ICON="󰂂"; CLASS="high"
        elif [[ ''${CAPACITY:-0} -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
        elif [[ ''${CAPACITY:-0} -gt 25 ]]; then ICON="󰁼"; CLASS="low"
        else ICON="󰁺"; CLASS="critical"; fi

        printf '{"text":"%s %s%%","class":"%s","tooltip":"Battery: %s%%\\nStatus: %s\\nHealth: %s\\nCycles: %s"}\n' \
          "$ICON" "$CAPACITY" "$CLASS" "$CAPACITY" "$STATUS" "$HEALTH" "$CYCLE_COUNT"
      '')

      # GPU menu for advanced GPU operations
      (pkgs.writeShellScriptBin "waybar-gpu-menu" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        CHOICE=$(printf '%s\n' \
          "Launch next app with NVIDIA" \
          "View GPU usage" \
          "Open nvidia-settings" \
          "Toggle Performance Mode" \
          | ${pkgs.wofi}/bin/wofi --dmenu --prompt "GPU Options:")

        case "$CHOICE" in
          "Launch next app with NVIDIA")
            touch /tmp/gpu-next-nvidia
            ${lib.optionalString cfg.notifications ''
              ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
            ''}
            ;;
          "View GPU usage")
            ${pkgs.kitty}/bin/kitty --title "GPU Monitor" -e ${pkgs.nvtopPackages.full}/bin/nvtop &
            ;;
          "Open nvidia-settings")
            command -v nvidia-settings >/dev/null && nvidia-settings &
            ;;
          "Toggle Performance Mode")
            command -v waybar-gpu-toggle >/dev/null && waybar-gpu-toggle
            ;;
        esac
      '')

      # System monitoring launcher  
      (pkgs.writeShellScriptBin "waybar-system-monitor" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        CHOICE=$(printf '%s\n' \
          "System Monitor (btop)" \
          "Disk Usage (baobab)" \
          "Network Settings" \
          "Power Settings" \
          "Temperature Monitor" \
          | ${pkgs.wofi}/bin/wofi --dmenu --prompt "System Tools:")

        case "$CHOICE" in
          "System Monitor (btop)")
            ${pkgs.kitty}/bin/kitty --title "System Monitor" -e ${pkgs.btop}/bin/btop &
            ;;
          "Disk Usage (baobab)")
            ${pkgs.baobab}/bin/baobab &
            ;;
          "Network Settings")
            ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
            ;;
          "Power Settings")
            if command -v gnome-power-statistics >/dev/null 2>&1; then
              gnome-power-statistics &
            else
              ${pkgs.kitty}/bin/kitty --title "Power Info" -e sh -c "${pkgs.acpi}/bin/acpi -V && read" &
            fi
            ;;
          "Temperature Monitor")
            ${pkgs.kitty}/bin/kitty --title "Sensors" -e sh -c "${pkgs.lm_sensors}/bin/sensors && read" &
            ;;
        esac
      '')
    ];

    #==========================================================================
    # VALIDATION - Assertions and checks
    #==========================================================================
    assertions = [
      {
        assertion = config.networking.networkmanager.enable;
        message = "waybar-system-tools requires NetworkManager to be enabled for network monitoring";
      }
    ];
  };
}