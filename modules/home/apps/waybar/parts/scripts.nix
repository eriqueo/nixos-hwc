# modules/home/apps/waybar/parts/scripts.nix
# Part (not a module): returns { bins = [ writeShellScriptBin … ]; }
{ pkgs, lib, ... }:

let
  # everything scripts need at runtime
  runtimePath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnused
    pkgs.gawk
    pkgs.gnugrep
    pkgs.procps
    pkgs.jq
    pkgs.networkmanager  # nmcli
    pkgs.iw              # iw
    pkgs.ethtool
    pkgs.mesa-demos      # glxinfo
    pkgs.lm_sensors      # sensors
    pkgs.kitty
    pkgs.btop
    pkgs.speedtest-cli
    pkgs.nvtopPackages.full
    pkgs.libnotify       # notify-send
    pkgs.wofi
    pkgs.curl
    pkgs.acpi
    pkgs.powertop
    pkgs.mission-center or null
    pkgs.hyprland        # hyprctl
    pkgs.linuxPackages.nvidia_x11 or null # nvidia-smi if present
  ] // builtins; # allow `or null` safely

  mk = name: text:
    pkgs.writeShellScriptBin name ''
      #!/usr/bin/env bash
      set -euo pipefail
      export PATH=${runtimePath}:$PATH
      ${text}
    '';
in
{
  bins = [
    # ── GPU tools ────────────────────────────────────────────────────────────
    (mk "waybar-gpu-status" ''
      GPU_MODE_FILE="/tmp/gpu-mode"
      DEFAULT_MODE="intel"
      [[ -f "$GPU_MODE_FILE" ]] || echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
      CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")

      CURRENT_GPU=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
      NVIDIA_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
      NVIDIA_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")

      case "$CURRENT_MODE" in
        intel)        ICON="󰢮"; CLASS="intel";       TOOLTIP="Intel Mode: $CURRENT_GPU" ;;
        nvidia)       ICON="󰾲"; CLASS="nvidia";      TOOLTIP="NVIDIA Mode: $CURRENT_GPU\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C" ;;
        performance)  ICON="⚡";  CLASS="performance"; TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C" ;;
        *)            ICON="󰢮"; CLASS="intel";       TOOLTIP="Intel Mode (Default): $CURRENT_GPU" ;;
      esac

      echo "{\"text\":\"$ICON\",\"class\":\"$CLASS\",\"tooltip\":\"$TOOLTIP\"}"
    '')
    (mk "waybar-gpu-toggle" ''
      GPU_MODE_FILE="/tmp/gpu-mode"
      CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")
      case "$CURRENT_MODE" in
        intel)        echo "performance" > "$GPU_MODE_FILE"; notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card ;;
        performance)  echo "intel"       > "$GPU_MODE_FILE"; notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card ;;
        *)            echo "intel"       > "$GPU_MODE_FILE"; notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card ;;
      esac
      pkill -SIGUSR1 waybar 2>/dev/null || true
    '')
    (mk "waybar-gpu-launch" ''
      if [[ $# -eq 0 ]]; then echo "Usage: waybar-gpu-launch <application> [args...]"; exit 1; fi
      GPU_MODE_FILE="/tmp/gpu-mode"
      CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")
      NEXT_NVIDIA_FILE="/tmp/gpu-next-nvidia"

      if [[ -f "$NEXT_NVIDIA_FILE" ]]; then
        rm -f "$NEXT_NVIDIA_FILE"
        exec nvidia-offload "$@"
      fi

      case "$CURRENT_MODE" in
        performance)
          case "$1" in
            blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|librewolf) exec nvidia-offload "$@" ;;
            *) exec "$@" ;;
          esac
          ;;
        nvidia) exec nvidia-offload "$@" ;;
        *)      exec "$@" ;;
      esac
    '')
    (mk "waybar-gpu-menu" ''
      CHOICE=$(printf '%s\n' \
        "Launch next app with NVIDIA" \
        "View GPU usage" \
        "Open nvidia-settings" \
        "Toggle Performance Mode" | wofi --dmenu --prompt "GPU Options:")
      case "$CHOICE" in
        "Launch next app with NVIDIA") touch /tmp/gpu-next-nvidia; notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card ;;
        "View GPU usage")              kitty --title "GPU Monitor" -e nvtop & ;;
        "Open nvidia-settings")        nvidia-settings & ;;
        "Toggle Performance Mode")     waybar-gpu-toggle ;;
      esac
    '')

    # ── Monitoring tools ─────────────────────────────────────────────────────
    (mk "waybar-workspace-switcher" ''
      [[ $# -gt 0 ]] || exit 1
      WORKSPACE="$1"
      CURRENT="$(hyprctl activewindow -j | jq -r '.workspace.id' 2>/dev/null || echo 1)"
      if [[ "$CURRENT" != "$WORKSPACE" ]]; then
        hyprctl dispatch workspace "$WORKSPACE"
        WORKSPACE_INFO="$(hyprctl workspaces -j | jq -r ".[] | select(.id==$WORKSPACE) | \"Workspace $WORKSPACE: \(.windows) windows\"" 2>/dev/null || echo "Workspace $WORKSPACE")"
        notify-send "Workspace" "$WORKSPACE_INFO" -t 1000 -i desktop
      fi
    '')
    (mk "waybar-resource-monitor" ''
      CPU_USAGE="$(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | sed 's/%us,//')"
      MEM_INFO="$(free | grep Mem)"
      MEM_TOTAL="$(echo "$MEM_INFO" | awk '{print $2}')"
      MEM_USED="$(echo  "$MEM_INFO" | awk '{print $3}')"
      MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))
      TEMP="$(sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | awk '{print $3}' | sed 's/+//;s/°C.*//' || echo 0)"
      # Intentionally stdout nothing for Waybar "exec" polling modules that only care about exit code.
      exit 0
    '')
    (mk "waybar-network-status" ''
      ACTIVE_CONN="$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -v ":loopback:\\|:tun:\\|:bridge:" | head -1)"
      if [[ -z "$ACTIVE_CONN" ]]; then
        echo '{"text":"󰤭","class":"disconnected","tooltip":"No network connection"}'
        exit 0
      fi
      CONN_NAME="$(echo "$ACTIVE_CONN" | cut -d: -f1)"
      CONN_TYPE="$(echo "$ACTIVE_CONN" | cut -d: -f2)"
      DEVICE="$(echo "$ACTIVE_CONN" | cut -d: -f3)"

      if [[ "$CONN_TYPE" == "802-11-wireless" ]]; then
        SIGNAL="$(nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')"
        SPEED="$(iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")"
        if   [[ ${SIGNAL:-0} -gt 75 ]]; then ICON="󰤨"; CLASS="excellent"
        elif [[ ${SIGNAL:-0} -gt 50 ]]; then ICON="󰤥"; CLASS="good"
        elif [[ ${SIGNAL:-0} -gt 25 ]]; then ICON="󰤢"; CLASS="fair"
        else                                 ICON="󰤟"; CLASS="poor"
        fi
        TOOLTIP="WiFi: $CONN_NAME\nSignal: ${SIGNAL:-0}%\nSpeed: $SPEED"
      else
        ICON="󰈀"; CLASS="ethernet"
        SPEED="$(ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")"
        TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
      fi

      echo "{\"text\":\"$ICON\",\"class\":\"$CLASS\",\"tooltip\":\"$TOOLTIP\"}"
    '')
    (mk "waybar-battery-health" ''
      BATTERY_PATH="/sys/class/power_supply/BAT0"
      if [[ ! -d "$BATTERY_PATH" ]]; then
        echo '{"text":"󰂑","tooltip":"No battery detected"}'
        exit 0
      fi
      CAPACITY="$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo 0)"
      STATUS="$(cat "$BATTERY_PATH/status"   2>/dev/null || echo Unknown)"
      HEALTH="$(cat "$BATTERY_PATH/health"   2>/dev/null || echo Unknown)"
      CYCLE_COUNT="$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo Unknown)"
      if [[ "$STATUS" == "Discharging" ]]; then
        POWER_NOW="$(cat "$BATTERY_PATH/power_now"  2>/dev/null || echo 0)"
        ENERGY_NOW="$(cat "$BATTERY_PATH/energy_now" 2>/dev/null || echo 0)"
        if [[ ''${POWER_NOW:-0} -gt 0 ]]; then
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
      if   [[ ''${CAPACITY:-0} -gt 90 ]]; then ICON="󰁹"; CLASS="full"
      elif [[ ''${CAPACITY:-0} -gt 75 ]]; then ICON="󰂂"; CLASS="high"
      elif [[ ''${CAPACITY:-0} -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
      elif [[ ''${CAPACITY:-0} -gt 25 ]]; then ICON="󰁼"; CLASS="low"
      else                                   ICON="󰁺"; CLASS="critical"
      fi
      [[ "$STATUS" == "Charging" ]] && ICON="󰂄" && CLASS="charging"
      echo "{\"text\":\"''$ICON ''${CAPACITY}%\",\"class\":\"''$CLASS\",\"tooltip\":\"Battery: ''${CAPACITY}%\\nStatus: ''$STATUS\\nHealth: ''$HEALTH\\nCycles: ''$CYCLE_COUNT\\nTime: ''$TIME_STR\"}"
    '')


    # ── System control helpers ───────────────────────────────────────────────
    (mk "waybar-disk-usage-gui" ''baobab &'')

    (mk "waybar-system-monitor" ''kitty --title "System Monitor" -e btop &'')

    (mk "waybar-network-settings" ''
      CHOICE=$(printf '%s\n' \
        "WiFi Manager (nmtui)" \
        "Network Connections Editor" \
        "VPN Status" \
        "Network Speed Test" \
        "Network Diagnostics" | wofi --dmenu --prompt "Network Tools:")

      case "$CHOICE" in
        "WiFi Manager (nmtui)")       kitty --title "WiFi Manager" -e nmtui & ;;
        "Network Connections Editor") nm-connection-editor & ;;
        "VPN Status")                 kitty --title "VPN Status" -e sh -c 'echo "=== VPN Status ==="; echo; vpnstatus; echo; echo "Commands: vpnon | vpnoff"; read -p "Enter to close..."' & ;;
        "Network Speed Test")         kitty --title "Network Speed Test" -e sh -c 'speedtest-cli; read -p "Enter to close..."' & ;;
        "Network Diagnostics")        kitty --title "Network Diagnostics" -e sh -c 'echo "=== Network Diagnostics ==="; echo; echo "Current IP:"; curl -s ifconfig.me; echo; echo "Active Connections:"; nmcli connection show --active; echo; echo "WiFi Networks:"; nmcli dev wifi; echo; read -p "Enter to close..."' & ;;
      esac
    '')

    (mk "waybar-power-settings" ''
      if command -v gnome-power-statistics >/dev/null 2>&1; then
        gnome-power-statistics &
      elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
        xfce4-power-manager-settings &
      else
        kitty --title "Power Info" -e sh -c "acpi -V && powertop --dump && read" &
      fi
    '')

    (mk "waybar-sensor-viewer" ''
      if command -v mission-center >/dev/null 2>&1; then
        mission-center &
      else
        kitty --title "Sensors" -e sh -c "sensors && read" &
      fi
    '')
  ];
}
