# nixos-hwc/modules/home/waybar-scripts.nix
#
# Home UI: Waybar helper scripts (HM consumer)
# Ships small CLI tools Waybar calls (no Waybar config here).
#
# DEPENDENCIES (Upstream):
#   - home-manager.nixosModules.home-manager
#   - gpu toggles (gpu-toggle/gpu-next/gpu-launch/gpu-status) are provided by modules/system/gpu.nix
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports + enables)
#
# USAGE:
#   # in profiles/workstation.nix
#   imports = [ ../modules/home/waybar-scripts.nix ];
#   hwc.desktop.waybar.scripts.enable = true;

{ config, lib, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.desktop.waybar.scripts;

  networkStatus = pkgs.writeShellScriptBin "network-status" ''
    #!/usr/bin/env bash
    ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | head -1)
    if [[ -z "$ACTIVE_CONN" ]]; then
      echo '{"text":"󰤭","class":"disconnected","tooltip":"No network connection"}'
      exit 0
    fi
    CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
    CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
    DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)
    if [[ "$CONN_TYPE" == "wifi" ]]; then
      SIGNAL=$(nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')
      SPEED=$(iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")
      if [[ ${SIGNAL:-0} -gt 75 ]]; then ICON="󰤨"; CLASS="excellent"
      elif [[ ${SIGNAL:-0} -gt 50 ]]; then ICON="󰤥"; CLASS="good"
      elif [[ ${SIGNAL:-0} -gt 25 ]]; then ICON="󰤢"; CLASS="fair"
      else ICON="󰤟"; CLASS="poor"; fi
      TOOLTIP="WiFi: $CONN_NAME\nSignal: ${SIGNAL:-0}%\nSpeed: $SPEED"
    else
      ICON="󰈀"; CLASS="ethernet"
      SPEED=$(ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
      TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
    fi
    echo "{\"text\":\"$ICON\",\"class\":\"$CLASS\",\"tooltip\":\"$TOOLTIP\"}"
  '';

  batteryHealth = pkgs.writeShellScriptBin "battery-health" ''
    #!/usr/bin/env bash
    B="/sys/class/power_supply/BAT0"
    if [[ ! -d "$B" ]]; then
      echo '{"text":"󰂑","tooltip":"No battery detected"}'
      exit 0
    fi
    CAPACITY=$(cat "$B/capacity" 2>/dev/null || echo "0")
    STATUS=$(cat "$B/status" 2>/dev/null || echo "Unknown")
    HEALTH=$(cat "$B/health" 2>/dev/null || echo "Unknown")
    CYCLE_COUNT=$(cat "$B/cycle_count" 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Charging" ]]; then ICON="󰂄"; CLASS="charging"
    elif [[ ${CAPACITY:-0} -gt 90 ]]; then ICON="󰁹"; CLASS="full"
    elif [[ ${CAPACITY:-0} -gt 75 ]]; then ICON="󰂂"; CLASS="high"
    elif [[ ${CAPACITY:-0} -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
    elif [[ ${CAPACITY:-0} -gt 25 ]]; then ICON="󰁼"; CLASS="low"
    else ICON="󰁺"; CLASS="critical"; fi
    echo "{\"text\":\"$ICON ${CAPACITY}%\",\"class\":\"$CLASS\",\"tooltip\":\"Battery: ${CAPACITY}%\\nStatus: $STATUS\\nHealth: $HEALTH\\nCycles: $CYCLE_COUNT\"}"
  '';

  gpuMenu = pkgs.writeShellScriptBin "gpu-menu" ''
    #!/usr/bin/env bash
    CHOICE=$(printf "%s\n%s\n%s\n%s\n" \
      "Launch next app with NVIDIA" \
      "View GPU usage" \
      "Open nvidia-settings" \
      "Toggle Performance Mode" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "GPU Options:")
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

  diskUsage = pkgs.writeShellScriptBin "disk-usage-gui" ''${pkgs.baobab}/bin/baobab & '';
  systemMonitor = pkgs.writeShellScriptBin "system-monitor" ''${pkgs.kitty}/bin/kitty --title "System Monitor" -e ${pkgs.btop}/bin/btop & '';
  networkSettings = pkgs.writeShellScriptBin "network-settings" ''${pkgs.networkmanagerapplet}/bin/nm-connection-editor & '';
  powerSettings = pkgs.writeShellScriptBin "power-settings" ''
    if command -v gnome-power-statistics >/dev/null 2>&1; then gnome-power-statistics &
    elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then xfce4-power-manager-settings &
    else ${pkgs.kitty}/bin/kitty --title "Power Info" -e sh -c "${pkgs.acpi}/bin/acpi -V && ${pkgs.powertop}/bin/powertop --dump && read" & fi
  '';
  sensorViewer = pkgs.writeShellScriptBin "sensor-viewer" ''
    if command -v mission-center >/dev/null 2>&1; then mission-center &
    else ${pkgs.kitty}/bin/kitty --title "Sensors" -e sh -c "${pkgs.lm_sensors}/bin/sensors && read" & fi
  '';
in
{
  options.hwc.desktop.waybar.scripts.enable =
    lib.mkEnableOption "Install Waybar helper scripts";

  config = lib.mkIf cfg.enable {
    home.packages = [
      networkStatus
      batteryHealth
      gpuMenu
      diskUsage
      systemMonitor
      networkSettings
      powerSettings
      sensorViewer
      # runtime deps
      pkgs.wofi pkgs.kitty pkgs.btop pkgs.baobab pkgs.networkmanagerapplet
      pkgs.ethtool pkgs.iw pkgs.mesa-demos pkgs.lm_sensors pkgs.acpi pkgs.powertop
      pkgs.nvtopPackages.full
    ];
  };
}
