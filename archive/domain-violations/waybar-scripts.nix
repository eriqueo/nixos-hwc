# nixos-hwc/modules/home/waybar-scripts.nix
#
# Home UI: Waybar helper scripts (HM module)
# Provides small CLI helpers used by the Waybar config.
#
# DEPENDENCIES (Upstream):
#   - Imported via home-manager.users.<user>.imports
#
# USED BY (Downstream):
#   - modules/home/waybar.nix (exec lines reference these scripts)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (inside home-manager.users.<user>.imports)

{ lib, pkgs, ... }:

let
  # --- Network status widget ---
  networkStatus = pkgs.writeShellScriptBin "network-status" ''
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
      if [[ ${SIGNAL:-0} -gt 75 ]]; then ICON="󰤨"; CLASS="excellent"
      elif [[ ${SIGNAL:-0} -gt 50 ]]; then ICON="󰤥"; CLASS="good"
      elif [[ ${SIGNAL:-0} -gt 25 ]]; then ICON="󰤢"; CLASS="fair"
      else ICON="󰤟"; CLASS="poor"; fi
      TOOLTIP="WiFi: $CONN_NAME\nSignal: $SIGNAL%\nSpeed: $SPEED"
    else
      ICON="󰈀"; CLASS="ethernet"
      SPEED=$(ethtool "$DEVICE" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' || echo "Unknown")
      TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
    fi

    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$ICON" "$CLASS" "$TOOLTIP"
  '';

  # --- Battery widget (no Nix ${} in strings!) ---
  batteryHealth = pkgs.writeShellScriptBin "battery-health" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BATTERY_PATH="/sys/class/power_supply/BAT0"
    CAPACITY="0"; STATUS="Unknown"; HEALTH="Unknown"; CYCLE_COUNT="Unknown"

    if [[ -d "$BATTERY_PATH" ]]; then
      CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
      STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
      HEALTH=$(cat "$BATTERY_PATH/health" 2:/dev/null || echo "Unknown")
      CYCLE_COUNT=$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")
    fi

    if [[ "$STATUS" == "Charging" ]]; then ICON="󰂄"; CLASS="charging"
    elif [[ ${CAPACITY:-0} -gt 90 ]]; then ICON="󰁹"; CLASS="full"
    elif [[ ${CAPACITY:-0} -gt 75 ]]; then ICON="󰂂"; CLASS="high"
    elif [[ ${CAPACITY:-0} -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
    elif [[ ${CAPACITY:-0} -gt 25 ]]; then ICON="󰁼"; CLASS="low"
    else ICON="󰁺"; CLASS="critical"; fi

    printf '{"text":"%s %s%%","class":"%s","tooltip":"Battery: %s%%\nStatus: %s\nHealth: %s\nCycles: %s"}\n' \
      "$ICON" "$CAPACITY" "$CLASS" "$CAPACITY" "$STATUS" "$HEALTH" "$CYCLE_COUNT"
  '';

  # --- GPU menu (optional) ---
  gpuMenu = pkgs.writeShellScriptBin "gpu-menu" ''
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
        command -v notify-send >/dev/null && notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
        ;;
      "View GPU usage")
        ${pkgs.kitty}/bin/kitty --title "GPU Monitor" -e ${pkgs.nvtopPackages.full}/bin/nvtop &
        ;;
      "Open nvidia-settings")
        command -v nvidia-settings >/dev/null && nvidia-settings &
        ;;
      "Toggle Performance Mode")
        command -v gpu-toggle >/dev/null && gpu-toggle
        ;;
    esac
  '';

  diskUsage = pkgs.writeShellScriptBin "disk-usage-gui" ''
    #!/usr/bin/env bash
    ${pkgs.baobab}/bin/baobab &
  '';

  systemMonitor = pkgs.writeShellScriptBin "system-monitor" ''
    #!/usr/bin/env bash
    ${pkgs.kitty}/bin/kitty --title "System Monitor" -e ${pkgs.btop}/bin/btop &
  '';

  networkSettings = pkgs.writeShellScriptBin "network-settings" ''
    #!/usr/bin/env bash
    ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
  '';

  powerSettings = pkgs.writeShellScriptBin "power-settings" ''
    #!/usr/bin/env bash
    if command -v gnome-power-statistics >/dev/null 2>&1; then
      gnome-power-statistics &
    elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
      xfce4-power-manager-settings &
    else
      ${pkgs.kitty}/bin/kitty --title "Power Info" -e sh -c "${pkgs.acpi}/bin/acpi -V && ${pkgs.powertop}/bin/powertop --dump && read" &
    fi
  '';

  sensorViewer = pkgs.writeShellScriptBin "sensor-viewer" ''
    #!/usr/bin/env bash
    if command -v mission-center >/dev/null 2>&1; then
      mission-center &
    else
      ${pkgs.kitty}/bin/kitty --title "Sensors" -e sh -c "${pkgs.lm_sensors}/bin/sensors && read" &
    fi
  '';
in
{
  # This is a Home-Manager module: it contributes to `home.*`, not `services.*`.
  # Import this file ONLY inside home-manager.users.<user>.imports.
  home.packages = [
    networkStatus
    batteryHealth
    gpuMenu
    diskUsage
    systemMonitor
    networkSettings
    powerSettings
    sensorViewer
    # plus any GUI helpers these rely on:
    pkgs.baobab
    pkgs.networkmanagerapplet
    pkgs.nvtopPackages.full
    pkgs.btop
    pkgs.lm_sensors
    pkgs.ethtool
    pkgs.iw
    pkgs.mesa-demos
    pkgs.mpc-cli
    pkgs.wofi
    pkgs.kitty
  ];
}
