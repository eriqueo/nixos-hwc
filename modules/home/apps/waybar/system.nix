# nixos-hwc/modules/home/apps/waybar/system.nix
#
# WAYBAR SYSTEM INTEGRATION - Cross-stream infrastructure tools
# Charter v6 compliant: lives in Waybar folder but exports to system domain
#
# DEPENDENCIES (Upstream):
#   - pkgs: jq, libnotify, procps, lm_sensors, ethtool, iw, kitty, etc.
#
# USED BY (Downstream):
#   - profiles/workstation.nix (system imports)
#   - modules/home/apps/waybar/default.nix (assumes scripts are available)
#
# USAGE:
#   let system = import ./system.nix { inherit config lib pkgs; };
#   in {
#     environment.systemPackages = system.packages;
#     systemd.user.services = system.services;
#   }
#

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.waybarTools;

  inherit (pkgs)
    writeShellScriptBin jq libnotify procps lm_sensors ethtool iw curl
    networkmanager networkmanagerapplet kitty nvtopPackages
    speedtest-cli acpi powertop baobab btop wofi mesa-demos linuxPackages;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.infrastructure.waybarTools = {
    enable = lib.mkEnableOption "Waybar helper tools for system-wide access";

    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show notifications for Waybar tool actions";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      #========================================================================
      # GPU TOOLS
      #========================================================================
      (writeShellScriptBin "waybar-gpu-status" ''
        #!/usr/bin/env bash
        set -euo pipefail

        GPU_MODE_FILE="/tmp/gpu-mode"
        DEFAULT_MODE="intel"

        if [[ ! -f "$GPU_MODE_FILE" ]]; then
          echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
        fi
        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")

        CURRENT_GPU=$(${mesa-demos}/bin/glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
        NVIDIA_POWER=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        NVIDIA_TEMP=$(${linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")

        case "$CURRENT_MODE" in
          "intel") ICON="󰢮"; CLASS="intel"; TOOLTIP="Intel Mode: $CURRENT_GPU" ;;
          "nvidia") ICON="󰾲"; CLASS="nvidia"; TOOLTIP="NVIDIA Mode: $CURRENT_GPU\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C" ;;
          "performance") ICON="⚡"; CLASS="performance"; TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C" ;;
          *) ICON="󰢮"; CLASS="intel"; TOOLTIP="Intel Mode (Default): $CURRENT_GPU" ;;
        esac

        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')

      (writeShellScriptBin "waybar-gpu-toggle" ''
        #!/usr/bin/env bash
        set -euo pipefail

        GPU_MODE_FILE="/tmp/gpu-mode"
        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

        case "$CURRENT_MODE" in
          "intel")
            echo "performance" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''${libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card''}
            ;;
          "performance")
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''${libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card''}
            ;;
          *)
            echo "intel" > "$GPU_MODE_FILE"
            ${lib.optionalString cfg.notifications ''${libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card''}
            ;;
        esac
        ${procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true
      '')

      (writeShellScriptBin "waybar-gpu-menu" ''
        #!/usr/bin/env bash
        set -euo pipefail
        CHOICE=$(echo -e "Launch next app with NVIDIA\nView GPU usage\nOpen nvidia-settings\nToggle Performance Mode" | ${wofi}/bin/wofi --dmenu --prompt "GPU Options:")

        case "$CHOICE" in
          "Launch next app with NVIDIA") touch /tmp/gpu-next-nvidia; ${lib.optionalString cfg.notifications ''${libnotify}/bin/notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card''} ;;
          "View GPU usage") ${kitty}/bin/kitty --title "GPU Monitor" -e ${nvtopPackages.full}/bin/nvtop & ;;
          "Open nvidia-settings") nvidia-settings & ;;
          "Toggle Performance Mode") waybar-gpu-toggle ;;
        esac
      '')

      #========================================================================
      # NETWORK TOOLS
      #========================================================================
      (writeShellScriptBin "waybar-network-status" ''
        #!/usr/bin/env bash
        set -euo pipefail
        ACTIVE_CONN=$(${networkmanager}/bin/nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -v ":loopback:\|:tun:\|:bridge:" | head -1)
        if [[ -z "$ACTIVE_CONN" ]]; then
          echo "{\"text\": \"󰤭\", \"class\": \"disconnected\", \"tooltip\": \"No network connection\"}"
          exit 0
        fi
        CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
        CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
        DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)
        if [[ "$CONN_TYPE" == "802-11-wireless" ]]; then
          SIGNAL=$(${networkmanager}/bin/nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')
          SPEED=$(${iw}/bin/iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")
          if [[ $SIGNAL -gt 75 ]]; then ICON="󰤨"; CLASS="excellent"
          elif [[ $SIGNAL -gt 50 ]]; then ICON="󰤥"; CLASS="good"
          elif [[ $SIGNAL -gt 25 ]]; then ICON="󰤢"; CLASS="fair"
          else ICON="󰤟"; CLASS="poor"; fi
          TOOLTIP="WiFi: $CONN_NAME\nSignal: $SIGNAL%\nSpeed: $SPEED"
        else
          ICON="󰈀"; CLASS="ethernet"; SPEED=$(${ethtool}/bin/ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
          TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
        fi
        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')

      #========================================================================
      # BATTERY
      #========================================================================
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
        TOOLTIP="Battery: $CAPACITY%\nStatus: $STATUS"
        if [[ "$STATUS" == "Charging" ]]; then ICON="󰂄"; CLASS="charging"
        elif [[ $CAPACITY -gt 90 ]]; then ICON="󰁹"; CLASS="full"
        elif [[ $CAPACITY -gt 75 ]]; then ICON="󰂂"; CLASS="high"
        elif [[ $CAPACITY -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
        elif [[ $CAPACITY -gt 25 ]]; then ICON="󰁼"; CLASS="low"
        else ICON="󰁺"; CLASS="critical"; fi
        echo "{\"text\": \"$ICON $CAPACITY%\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')

      #========================================================================
      # SYSTEM UTILITIES
      #========================================================================
      (writeShellScriptBin "waybar-system-monitor" ''
        #!/usr/bin/env bash
        ${kitty}/bin/kitty --title "System Monitor" -e ${btop}/bin/btop &
      '')

      (writeShellScriptBin "waybar-disk-usage-gui" ''
        #!/usr/bin/env bash
        ${baobab}/bin/baobab &
      '')
    ];

    systemd.user.services = { };
  };
}
