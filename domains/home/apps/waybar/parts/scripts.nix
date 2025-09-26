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
  "gpu-status" = sh "waybar-gpu-status" ''
    GPU_MODE_FILE="/tmp/gpu-mode"
    DEFAULT_MODE="intel"
    [[ -f "''$GPU_MODE_FILE" ]] || echo "''$DEFAULT_MODE" > "''$GPU_MODE_FILE"
    CURRENT_MODE=$(cat "''$GPU_MODE_FILE" 2>/dev/null || echo "''$DEFAULT_MODE")

    CURRENT_GPU=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
    NVIDIA_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | grep -E "^[0-9.]+$" || echo "0")
    NVIDIA_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | grep -E "^[0-9.]+$" || echo "0")

    case "''$CURRENT_MODE" in
      intel)
        ICON="󰢮"
        CLASS="intel"
        TOOLTIP="Intel Mode: ''$CURRENT_GPU"
        ;;
      nvidia)
        ICON="󰾲"
        CLASS="nvidia"
        TOOLTIP="NVIDIA Mode: ''$CURRENT_GPU - Power: ''${NVIDIA_POWER}W | Temp: ''${NVIDIA_TEMP}C"
        ;;
      performance)
        ICON="⚡"
        CLASS="performance"
        TOOLTIP="Performance Mode: Auto-GPU Selection - NVIDIA: ''${NVIDIA_POWER}W | ''${NVIDIA_TEMP}C"
        ;;
      *)
        ICON="󰢮"
        CLASS="intel"
        TOOLTIP="Intel Mode (Default): ''$CURRENT_GPU"
        ;;
    esac

    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "''$ICON" "''$CLASS" "''$TOOLTIP"
  '';

  "gpu-toggle" = sh "waybar-gpu-toggle" ''
    GPU_MODE_FILE="/tmp/gpu-mode"
    CURRENT_MODE=$(cat "''$GPU_MODE_FILE" 2>/dev/null || echo "intel")
    case "''$CURRENT_MODE" in
      intel)
        echo "performance" > "''$GPU_MODE_FILE"
        notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
        ;;
      performance)
        echo "intel" > "''$GPU_MODE_FILE"
        notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
        ;;
      *)
        echo "intel" > "''$GPU_MODE_FILE"
        notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
        ;;
    esac
    pkill -SIGUSR1 waybar 2>/dev/null || true
  '';

  "gpu-launch" = sh "waybar-gpu-launch" ''
    if [[ ''$# -eq 0 ]]; then
      echo "Usage: waybar-gpu-launch <application> [args...]"
      exit 1
    fi

    GPU_MODE_FILE="/tmp/gpu-mode"
    CURRENT_MODE=$(cat "''$GPU_MODE_FILE" 2>/dev/null || echo "intel")
    NEXT_NVIDIA_FILE="/tmp/gpu-next-nvidia"

    if [[ -f "''$NEXT_NVIDIA_FILE" ]]; then
      rm "''$NEXT_NVIDIA_FILE"
      exec nvidia-offload "''$@"
    fi

    case "''$CURRENT_MODE" in
      performance)
        case "''$1" in
          blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|librewolf)
            exec nvidia-offload "''$@"
            ;;
          *)
            exec "''$@"
            ;;
        esac
        ;;
      nvidia)
        exec nvidia-offload "''$@"
        ;;
      *)
        exec "''$@"
        ;;
    esac
  '';

  "gpu-menu" = sh "waybar-gpu-menu" ''
    CHOICE=$(printf "Launch next app with NVIDIA\\nView GPU usage\\nOpen nvidia-settings\\nToggle Performance Mode" | wofi --dmenu --prompt "GPU Options:")
    case "''$CHOICE" in
      "Launch next app with NVIDIA")
        touch /tmp/gpu-next-nvidia
        notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
        ;;
      "View GPU usage")
        kitty --title "GPU Monitor" -e nvtop &
        ;;
      "Open nvidia-settings")
        nvidia-settings &
        ;;
      "Toggle Performance Mode")
        waybar-gpu-toggle
        ;;
    esac
  '';

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
}
