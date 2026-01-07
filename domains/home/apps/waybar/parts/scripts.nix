# modules/home/apps/waybar/parts/scripts.nix
{ pkgs, lib, pathBin }:
let
  sh = name: text: pkgs.writeShellScriptBin name ''
    set -euo pipefail
    export PATH=${pathBin}:$PATH
    ${text}
  '';
in
{
  "workspace-switcher" = sh "waybar-workspace-switcher" ''
    if [[ ''$# -eq 0 ]]; then
      exit 1
    fi
    WORKSPACE="''$1"
    CURRENT=$(hyprctl activewindow -j | jq -r '.workspace.id // 1' 2>/dev/null || echo "1")
    if [[ "''$CURRENT" != "''$WORKSPACE" ]]; then
      hyprctl dispatch workspace "''$WORKSPACE"
      WORKSPACE_INFO=$(hyprctl workspaces -j | jq -r ".[] | select(.id==''$WORKSPACE) | \"Workspace ''$WORKSPACE: \(.windows) windows\"" 2>/dev/null || echo "Workspace ''$WORKSPACE")
      notify-send "Workspace" "''$WORKSPACE_INFO" -t 1000 -i desktop
    fi
  '';

  "resource-monitor" = sh "waybar-resource-monitor" ''
    CPU_USAGE=$(awk '/^cpu /{u=''$2+''$4; t=''$2+''$3+''$4+''$5; if (NR==1){u1=u; t1=t;} else printf "%.0f", (u-u1) * 100 / (t-t1); }' <(grep 'cpu ' /proc/stat; sleep 1; grep 'cpu ' /proc/stat))

    MEM_INFO=$(free | grep Mem)
    MEM_TOTAL=$(echo "''$MEM_INFO" | awk '{print ''$2}')
    MEM_USED=$(echo "''$MEM_INFO" | awk '{print ''$3}')
    MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))

    TEMP=$(sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | awk '{print ''$3}' | sed 's/+//;s/°C.*//' || echo "0")

    printf '{"text":"CPU: %s%% MEM: %s%% TEMP: %s°C","class":"normal","tooltip":"CPU Usage: %s%%\\nMemory Usage: %s%%\\nTemperature: %s°C"}\n' \
           "''$CPU_USAGE" "''$MEM_PERCENT" "''$TEMP" "''$CPU_USAGE" "''$MEM_PERCENT" "''$TEMP"
  '';

 "network-status" = sh "waybar-network-status" ''
  ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -Ev ':(loopback|tun|tap|wireguard|tailscale|bridge):' | head -1 || true)

  if [[ -z "''$ACTIVE_CONN" ]]; then
    printf '{"text":"󰤭","class":"disconnected","tooltip":"No network connection"}\n'
    exit 0
  fi

  CONN_NAME=$(echo "''$ACTIVE_CONN" | cut -d: -f1)
  CONN_TYPE=$(echo "''$ACTIVE_CONN" | cut -d: -f2)
  DEVICE=$(echo "''$ACTIVE_CONN" | cut -d: -f3)

  if [[ "''$CONN_TYPE" == "802-11-wireless" ]]; then
    SIGNAL=$(nmcli -t -f IN-USE,SIGNAL dev wifi | awk -F: '$1=="*" {print $2; exit}')
    SPEED=$(iw dev "''$DEVICE" link 2>/dev/null | awk -F':' '/tx bitrate/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
    SIGNAL="''${SIGNAL:-0}"
    SPEED="''${SPEED:-Unknown}"

    if [[ ''$SIGNAL -gt 75 ]]; then
      ICON="󰤨"; CLASS="excellent"
    elif [[ ''$SIGNAL -gt 50 ]]; then
      ICON="󰤥"; CLASS="good"
    elif [[ ''$SIGNAL -gt 25 ]]; then
      ICON="󰤢"; CLASS="fair"
    else
      ICON="󰤟"; CLASS="poor"
    fi
    TOOLTIP="WiFi: ''$CONN_NAME\\nSignal: ''$SIGNAL%\\nSpeed: ''$SPEED"
  else
    ICON="󰈀"
    CLASS="ethernet"
    SPEED=$(ethtool "''$DEVICE" 2>/dev/null | awk -F': ' '/Speed:/ {print $2; exit}')
    SPEED="''${SPEED:-Unknown}"
    TOOLTIP="Ethernet: ''$CONN_NAME\\nSpeed: ''$SPEED"
  fi

  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "''$ICON" "''$CLASS" "''$TOOLTIP"
'';

  "battery-health" = sh "waybar-battery-health" ''
    BATTERY_PATH="/sys/class/power_supply/BAT0"

    if [[ ! -d "''$BATTERY_PATH" ]]; then
      printf '{"text":"󰂑","tooltip":"No battery detected"}\n'
      exit 0
    fi

    CAPACITY=$(cat "''$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
    STATUS=$(cat "''$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
    HEALTH=$(cat "''$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
    CYCLE_COUNT=$(cat "''$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")

    if [[ "''$STATUS" == "Discharging" ]]; then
      POWER_NOW=$(cat "''$BATTERY_PATH/power_now" 2>/dev/null || echo "0")
      ENERGY_NOW=$(cat "''$BATTERY_PATH/energy_now" 2>/dev/null || echo "0")
      if [[ ''${POWER_NOW:-0} -gt 0 ]]; then
        # hours as float: µWh / µW → hours
        HOURS_FLOAT=$(awk -v e="''$ENERGY_NOW" -v p="''$POWER_NOW" 'BEGIN { printf "%.2f", (e/p) }')
        HOURS_INT=''${HOURS_FLOAT%.*}
        FRACTION=$(awk -v h="''$HOURS_FLOAT" 'BEGIN { printf "%.2f", h - int(h) }')
        MINUTES=$(awk -v f="''$FRACTION" 'BEGIN { printf "%d", (f*60) }')
        TIME_STR="''${HOURS_INT}h ''${MINUTES}m"
      else
        TIME_STR="Unknown"
      fi
    else
      TIME_STR="N/A"
    fi
    
    ICON="󰁺"; CLASS="critical"
    if [[ ''$CAPACITY -gt 90 ]]; then
      ICON="󰁹"; CLASS="full"
    elif [[ ''$CAPACITY -gt 75 ]]; then
      ICON="󰂂"; CLASS="high"
    elif [[ ''$CAPACITY -gt 50 ]]; then
      ICON="󰁿"; CLASS="medium"
    elif [[ ''$CAPACITY -gt 25 ]]; then
      ICON="󰁼"; CLASS="low"
    fi
    if [[ "''$STATUS" == "Charging" ]]; then
      ICON="󰂄"; CLASS="charging"
    fi

    printf '{"text":"%s %s%%","class":"%s","tooltip":"Battery: %s%%\\nStatus: %s\\nHealth: %s\\nCycles: %s\\nTime: %s"}\n' \
           "''$ICON" "''$CAPACITY" "''$CLASS" "''$CAPACITY" "''$STATUS" "''$HEALTH" "''$CYCLE_COUNT" "''$TIME_STR"
  '';


  "system-monitor" = sh "waybar-system-monitor" ''
    kitty --title "System Monitor" -e btop &
  '';

  "network-settings" = sh "waybar-network-settings" ''
    CHOICE=$(printf "WiFi Manager (nmtui)\\nNetwork Connections Editor\\nVPN Status\\nNetwork Speed Test\\nNetwork Diagnostics" | wofi --dmenu --prompt "Network Tools:")
    case "''$CHOICE" in
      "WiFi Manager (nmtui)")
        kitty --title "WiFi Manager" -e nmtui &
        ;;
      "Network Connections Editor")
        nm-connection-editor &
        ;;
      "VPN Status")
        kitty --title "VPN Status" -e sh -c 'echo "=== VPN Status ==="; echo ""; if command -v vpnstatus >/dev/null; then vpnstatus; else echo "VPN status command not found"; fi; echo ""; read -p "Press Enter to close..."' &
        ;;
      "Network Speed Test")
        kitty --title "Network Speed Test" -e sh -c 'speedtest-cli; read -p "Press Enter to close..."' &
        ;;
      "Network Diagnostics")
        kitty --title "Network Diagnostics" -e sh -c 'echo "=== Network Diagnostics ==="; echo ""; echo "Current IP:"; curl -s ifconfig.me; echo ""; echo ""; echo "Active Connections:"; nmcli connection show --active; echo ""; echo "WiFi Networks:"; nmcli dev wifi; echo ""; read -p "Press Enter to close..."' &
        ;;
    esac
  '';

  "power-settings" = sh "waybar-power-settings" ''
    if command -v gnome-power-statistics >/dev/null 2>&1; then
      gnome-power-statistics &
    elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
      xfce4-power-manager-settings &
    else
      kitty --title "Power Info" -e sh -c "acpi -V && echo 'Press Enter to close...'; read" &
    fi
  '';

  "sensor-viewer" = sh "waybar-sensor-viewer" ''
    if command -v mission-center >/dev/null 2>&1; then
      mission-center &
    else
      kitty --title "Sensors" -e sh -c "sensors && echo 'Press Enter to close...'; read" &
    fi
  '';

  "fan-monitor" = sh "waybar-fan-monitor" ''
    # Find ThinkPad hwmon device dynamically (device numbers change across boots)
    THINKPAD_HWMON=$(grep -l "^thinkpad$" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | xargs dirname)

    if [[ -z "$THINKPAD_HWMON" ]]; then
      printf '{"text":"󰈐 N/A","class":"idle","tooltip":"ThinkPad hwmon not found"}\n'
      exit 0
    fi

    # Read fan speeds from ThinkPad hwmon
    FAN1=$(cat "$THINKPAD_HWMON/fan1_input" 2>/dev/null || echo "0")
    FAN2=$(cat "$THINKPAD_HWMON/fan2_input" 2>/dev/null || echo "0")

    # Get max fan speed for either fan
    MAX_FAN=$(( FAN1 > FAN2 ? FAN1 : FAN2 ))

    # Determine icon and class based on fan speed
    if [[ ''$MAX_FAN -gt 4000 ]]; then
      ICON="󰈐"  # High speed
      CLASS="critical"
    elif [[ ''$MAX_FAN -gt 3000 ]]; then
      ICON="󰈐"  # Medium-high speed
      CLASS="high"
    elif [[ ''$MAX_FAN -gt 2000 ]]; then
      ICON="󰈐"  # Medium speed
      CLASS="medium"
    elif [[ ''$MAX_FAN -gt 1000 ]]; then
      ICON="󰈐"  # Low speed
      CLASS="low"
    else
      ICON="󰈐"  # Idle
      CLASS="idle"
    fi

    printf '{"text":"%s %s","class":"%s","tooltip":"Fan 1: %s RPM\\nFan 2: %s RPM"}\n' \
           "''$ICON" "''$MAX_FAN" "''$CLASS" "''$FAN1" "''$FAN2"
  '';

  "load-average" = sh "waybar-load-average" ''
    # Read load average (1min, 5min, 15min)
    LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    LOAD1=$(echo "''$LOAD" | awk '{print $1}')
    LOAD5=$(echo "''$LOAD" | awk '{print $2}')
    LOAD15=$(echo "''$LOAD" | awk '{print $3}')

    # Get number of CPUs
    NCPUS=$(nproc)

    # Calculate percentage (load1 / ncpus * 100)
    PERCENT=$(awk -v load="''$LOAD1" -v ncpus="''$NCPUS" 'BEGIN {printf "%.0f", (load/ncpus)*100}')

    # Determine class based on load percentage
    if [[ ''$PERCENT -gt 90 ]]; then
      CLASS="critical"
    elif [[ ''$PERCENT -gt 70 ]]; then
      CLASS="high"
    elif [[ ''$PERCENT -gt 50 ]]; then
      CLASS="medium"
    else
      CLASS="normal"
    fi

    printf '{"text":"󰾆 %s","class":"%s","tooltip":"Load Average:\\n1min: %s\\n5min: %s\\n15min: %s\\nCPUs: %s"}\n' \
           "''$LOAD1" "''$CLASS" "''$LOAD1" "''$LOAD5" "''$LOAD15" "''$NCPUS"
  '';

  "power-profile" = sh "waybar-power-profile" ''
    # Try to get current power profile
    if command -v powerprofilesctl >/dev/null 2>&1; then
      PROFILE=$(powerprofilesctl get 2>/dev/null || echo "unknown")
    else
      PROFILE="unavailable"
    fi

    case "''$PROFILE" in
      "performance")
        ICON="󰓅"
        CLASS="performance"
        TOOLTIP="Power Profile: Performance"
        ;;
      "balanced")
        ICON="󰾅"
        CLASS="balanced"
        TOOLTIP="Power Profile: Balanced"
        ;;
      "power-saver")
        ICON="󰾆"
        CLASS="powersave"
        TOOLTIP="Power Profile: Power Saver"
        ;;
      *)
        ICON="󱐋"
        CLASS="unknown"
        TOOLTIP="Power Profile: Unknown"
        ;;
    esac

    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "''$ICON" "''$CLASS" "''$TOOLTIP"
  '';

  "power-profile-toggle" = sh "waybar-power-profile-toggle" ''
    if ! command -v powerprofilesctl >/dev/null 2>&1; then
      notify-send "Power Profile" "powerprofilesctl not available" -i battery
      exit 0
    fi

    CURRENT=$(powerprofilesctl get 2>/dev/null || echo "balanced")

    case "''$CURRENT" in
      "performance")
        powerprofilesctl set balanced
        notify-send "Power Profile" "Switched to Balanced" -i battery
        ;;
      "balanced")
        powerprofilesctl set power-saver
        notify-send "Power Profile" "Switched to Power Saver" -i battery-low
        ;;
      *)
        powerprofilesctl set performance
        notify-send "Power Profile" "Switched to Performance" -i battery-full-charged
        ;;
    esac
  '';

  "disk-space" = sh "waybar-disk-space" ''
    # Monitor key partitions
    ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    ROOT_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

    # Determine icon and class
    if [[ ''$ROOT_USAGE -gt 90 ]]; then
      ICON="󰝦"
      CLASS="critical"
    elif [[ ''$ROOT_USAGE -gt 75 ]]; then
      ICON="󰝤"
      CLASS="warning"
    else
      ICON="󰋊"
      CLASS="normal"
    fi

    # Get home partition if different from root
    HOME_PARTITION=$(df /home | tail -1 | awk '{print $1}')
    ROOT_PARTITION=$(df / | tail -1 | awk '{print $1}')

    if [[ "''$HOME_PARTITION" != "''$ROOT_PARTITION" ]]; then
      HOME_USAGE=$(df -h /home | awk 'NR==2 {print $5}' | tr -d '%')
      HOME_AVAIL=$(df -h /home | awk 'NR==2 {print $4}')
      TOOLTIP="Root: ''${ROOT_USAGE}% used (''${ROOT_AVAIL} free)\\nHome: ''${HOME_USAGE}% used (''${HOME_AVAIL} free)"
    else
      TOOLTIP="Root: ''${ROOT_USAGE}% used (''${ROOT_AVAIL} free)"
    fi

    printf '{"text":"%s %s%%","class":"%s","tooltip":"%s"}\n' \
           "''$ICON" "''$ROOT_USAGE" "''$CLASS" "''$TOOLTIP"
  '';

  "ollama-status" = sh "waybar-ollama-status" ''
    # Check if podman-ollama service is running
    if systemctl is-active --quiet podman-ollama.service; then
      STATUS="running"
      ICON="🦙"
      CLASS="running"
      TOOLTIP="Ollama: Running\\nClick to stop"
    else
      STATUS="stopped"
      ICON="🦙"
      CLASS="stopped"
      TOOLTIP="Ollama: Stopped\\nClick to start"
    fi

    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "''$ICON" "''$CLASS" "''$TOOLTIP"
  '';

  "ollama-toggle" = sh "waybar-ollama-toggle" ''
    # Toggle podman-ollama service
    if systemctl is-active --quiet podman-ollama.service; then
      notify-send "Ollama" "Stopping Ollama service..." -t 2000 -i dialog-information
      sudo systemctl stop podman-ollama.service
      notify-send "Ollama" "Ollama stopped" -t 2000 -i dialog-information
    else
      notify-send "Ollama" "Starting Ollama service..." -t 2000 -i dialog-information
      sudo systemctl start podman-ollama.service
      notify-send "Ollama" "Ollama started" -t 2000 -i dialog-information
    fi
  '';
}
