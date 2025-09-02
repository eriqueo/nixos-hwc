# -----------------------------------------------------------------------------
# FILE: modules/home-manager/ui/waybar.nix (STATUS BAR) - ENHANCED VERSION
# -----------------------------------------------------------------------------
{ config, lib, pkgs, ... }:

let
  colors = {
    # Base colors (Gruvbox Material inspired - much softer contrast)
    background = "#282828";      # Gruvbox material bg (warmer, softer than our dark blue)
    foreground = "#d4be98";      # Muted cream (less bright, easier on eyes)

    # Selection colors (softer)
    selection_bg = "#7daea3";    # Muted teal instead of bright cyan
    selection_fg = "#282828";

    # Cursor (softer)
    cursor = "#d4be98";
    cursor_text = "#282828";

    # URL/links (softer)
    url = "#7daea3";

    # Gruvbox Material inspired colors (much softer, muted)
    # Dark colors (normal) - desaturated for eye comfort
    color0  = "#32302F";  # softer black
    color1  = "#ea6962";  # muted red (less harsh than Nord)
    color2  = "#a9b665";  # muted green
    color3  = "#d8a657";  # warm muted yellow
    color4  = "#7daea3";  # soft teal-blue (instead of bright blue)
    color5  = "#d3869b";  # soft pink-purple
    color6  = "#89b482";  # muted aqua
    color7  = "#d4be98";  # soft cream (main foreground)

    # Bright colors - slightly brighter but still muted
    color8  = "#45403d";  # muted bright black
    color9  = "#ea6962";  # same muted red
    color10 = "#a9b665";  # same muted green
    color11 = "#d8a657";  # same muted yellow
    color12 = "#7daea3";  # same soft blue
    color13 = "#d3869b";  # same soft purple
    color14 = "#89b482";  # same muted aqua
    color15 = "#d4be98";  # same soft cream

    # Nord semantic colors for UI elements
    nord0  = "#1f2329";  # darkest (our custom background)
    nord1  = "#3b4252";  # dark
    nord2  = "#434c5e";  # medium dark
    nord3  = "#4c566a";  # medium
    nord4  = "#d8dee9";  # medium light
    nord5  = "#e5e9f0";  # light
    nord6  = "#f2f0e8";  # lightest (our custom foreground)
    nord7  = "#8fbcbb";  # frost cyan
    nord8  = "#88c0d0";  # frost blue
    nord9  = "#81a1c1";  # frost light blue
    nord10 = "#5e81ac";  # frost dark blue
    nord11 = "#bf616a";  # aurora red
    nord12 = "#d08770";  # aurora orange
    nord13 = "#ebcb8b";  # aurora yellow
    nord14 = "#a3be8c";  # aurora green
    nord15 = "#b48ead";  # aurora purple

    # Transparency values
    opacity_terminal = "0.95";
    opacity_inactive = "0.90";

    # CSS/Web colors (with # prefix for web use) - Gruvbox Material inspired
    css = {
      background = "#282828";
      foreground = "#d4be98";
      accent = "#7daea3";      # soft teal
      warning = "#d8a657";     # muted yellow
      error = "#ea6962";       # muted red
      success = "#a9b665";     # muted green
      info = "#7daea3";        # soft blue
    };
  };

  # Enhanced GPU Management Scripts with better feedback
  gpuStatus = pkgs.writeScriptBin "gpu-status" ''
    #!/usr/bin/env bash
    # Check current GPU status and return JSON for waybar

    GPU_MODE_FILE="/tmp/gpu-mode"
    DEFAULT_MODE="intel"

    # Initialize mode file if it doesn't exist
    if [[ ! -f "$GPU_MODE_FILE" ]]; then
      echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
    fi

    CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")

    # Get current GPU renderer with better detection
    CURRENT_GPU=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")

    # Get GPU power consumption and temperature (if available)
    NVIDIA_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    NVIDIA_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")

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
  '';

  # Enhanced workspace switcher with better feedback
  workspaceSwitcher = pkgs.writeScriptBin "workspace-switcher" ''
    #!/usr/bin/env bash
    # Enhanced workspace switching with visual feedback

    if [[ $# -eq 0 ]]; then
      echo "Usage: workspace-switcher <workspace_number>"
      exit 1
    fi

    WORKSPACE=$1

    # Get current workspace
    CURRENT=$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.workspace.id' 2>/dev/null || echo "1")

    if [[ "$CURRENT" != "$WORKSPACE" ]]; then
      # Switch workspace
      hyprctl dispatch workspace "$WORKSPACE"

      # Show notification with workspace info
      WORKSPACE_INFO=$(hyprctl workspaces -j | ${pkgs.jq}/bin/jq -r ".[] | select(.id==$WORKSPACE) | \"Workspace $WORKSPACE: \(.windows) windows\"" 2>/dev/null || echo "Workspace $WORKSPACE")
      notify-send "Workspace" "$WORKSPACE_INFO" -t 1000 -i desktop
    fi
  '';

  # System resource monitor (kept minimal; safe)
  resourceMonitor = pkgs.writeScriptBin "resource-monitor" ''
    #!/usr/bin/env bash
    # Monitor system resources (placeholder; safe to run)

    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    CPU_NUM=$(echo "$CPU_USAGE" | cut -d'.' -f1 | grep -o '[0-9]*' || echo "0")

    # Memory usage
    MEM_INFO=$(free | grep Mem)
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))

    # Temperature
    TEMP=$(sensors 2>/dev/null | grep -E "(Core 0|Tctl)" | head -1 | awk '{print $3}' | sed 's/+//;s/°C.*//' || echo "0")
    TEMP_NUM=$(echo "$TEMP" | cut -d'.' -f1 | grep -o '[0-9]*' || echo "0")

    exit 0
  '';

  # Enhanced network status with connection quality
  networkStatus = pkgs.writeScriptBin "network-status" ''
    #!/usr/bin/env bash
    # Enhanced network status with quality indicators

    # Get primary network connection (exclude loopback, VPN tunnels, and bridges)
    ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep -v ":loopback:\|:tun:\|:bridge:" | head -1)

    if [[ -z "$ACTIVE_CONN" ]]; then
      echo "{\"text\": \"󰤭\", \"class\": \"disconnected\", \"tooltip\": \"No network connection\"}"
      exit 0
    fi

    CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
    CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
    DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)

    if [[ "$CONN_TYPE" == "802-11-wireless" ]]; then
      # Get WiFi signal strength
      SIGNAL=$(nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')
      SPEED=$(iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")

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
      SPEED=$(ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
      TOOLTIP="Ethernet: $CONN_NAME\nSpeed: $SPEED"
    fi

    echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
  '';

  # Battery health monitor
  batteryHealth = pkgs.writeScriptBin "battery-health" ''
    #!/usr/bin/env bash
    # Monitor battery health and provide detailed info

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
  '';

  # System scripts (keeping existing ones)
  gpuToggle = pkgs.writeScriptBin "gpu-toggle" ''
    #!/usr/bin/env bash
    GPU_MODE_FILE="/tmp/gpu-mode"
    CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

    case "$CURRENT_MODE" in
      "intel")
        echo "performance" > "$GPU_MODE_FILE"
        notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
        ;;
      "performance")
        echo "intel" > "$GPU_MODE_FILE"
        notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
        ;;
      *)
        echo "intel" > "$GPU_MODE_FILE"
        notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
        ;;
    esac

    pkill -SIGUSR1 waybar 2>/dev/null || true
  '';

  gpuLaunch = pkgs.writeScriptBin "gpu-launch" ''
    #!/usr/bin/env bash
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
  '';

  gpuMenu = pkgs.writeScriptBin "gpu-menu" ''
    #!/usr/bin/env bash
    CHOICE=$(echo -e "Launch next app with NVIDIA\nView GPU usage\nOpen nvidia-settings\nToggle Performance Mode" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "GPU Options:")

    case "$CHOICE" in
      "Launch next app with NVIDIA")
        touch /tmp/gpu-next-nvidia
        notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
        ;;
      "View GPU usage")
        ${pkgs.kitty}/bin/kitty --title "GPU Monitor" -e ${pkgs.nvtopPackages.full}/bin/nvtop &
        ;;
      "Open nvidia-settings")
        nvidia-settings &
        ;;
      "Toggle Performance Mode")
        gpu-toggle
        ;;
    esac
  '';

  # System monitoring scripts
  diskUsage = pkgs.writeScriptBin "disk-usage-gui" ''
    #!/usr/bin/env bash
    ${pkgs.baobab}/bin/baobab &
  '';

  systemMonitor = pkgs.writeScriptBin "system-monitor" ''
    #!/usr/bin/env bash
    ${pkgs.kitty}/bin/kitty --title "System Monitor" -e ${pkgs.btop}/bin/btop &
  '';

  networkSettings = pkgs.writeScriptBin "network-settings" ''
    #!/usr/bin/env bash
    # Comprehensive network management menu

    CHOICE=$(echo -e "WiFi Manager (nmtui)\nNetwork Connections Editor\nVPN Status\nNetwork Speed Test\nNetwork Diagnostics" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "Network Tools:")

    case "$CHOICE" in
      "WiFi Manager (nmtui)")
        ${pkgs.kitty}/bin/kitty --title "WiFi Manager" -e ${pkgs.networkmanager}/bin/nmtui &
        ;;
      "Network Connections Editor")
        ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
        ;;
      "VPN Status")
        ${pkgs.kitty}/bin/kitty --title "VPN Status" -e sh -c 'echo "=== VPN Status ==="; echo ""; vpnstatus; echo ""; echo "Commands: vpnon (connect) | vpnoff (disconnect)"; echo ""; read -p "Press Enter to close..."' &
        ;;
      "Network Speed Test")
        ${pkgs.kitty}/bin/kitty --title "Network Speed Test" -e sh -c '${pkgs.speedtest-cli}/bin/speedtest-cli; read -p "Press Enter to close..."' &
        ;;
      "Network Diagnostics")
        ${pkgs.kitty}/bin/kitty --title "Network Diagnostics" -e sh -c 'echo "=== Network Diagnostics ==="; echo ""; echo "Current IP:"; curl -s ifconfig.me; echo ""; echo ""; echo "Active Connections:"; nmcli connection show --active; echo ""; echo "WiFi Networks:"; nmcli dev wifi; echo ""; read -p "Press Enter to close..."' &
        ;;
    esac
  '';

  powerSettings = pkgs.writeScriptBin "power-settings" ''
    #!/usr/bin/env bash
    if command -v gnome-power-statistics >/dev/null 2>&1; then
      gnome-power-statistics &
    elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
      xfce4-power-manager-settings &
    else
      ${pkgs.kitty}/bin/kitty --title "Power Info" -e sh -c "${pkgs.acpi}/bin/acpi -V && ${pkgs.powertop}/bin/powertop --dump && read" &
    fi
  '';

  sensorViewer = pkgs.writeScriptBin "sensor-viewer" ''
    #!/usr/bin/env bash
    if command -v mission-center >/dev/null 2>&1; then
      mission-center &
    else
      ${pkgs.kitty}/bin/kitty --title "Sensors" -e sh -c "${pkgs.lm_sensors}/bin/sensors && read" &
    fi
  '';

in

{
  # Enhanced dependencies
  home.packages = with pkgs; [
    pavucontrol
    swaynotificationcenter
    wlogout

    # GPU management scripts
    gpuStatus
    gpuToggle
    gpuLaunch
    gpuMenu

    # Enhanced system monitoring
    workspaceSwitcher
    resourceMonitor
    networkStatus
    batteryHealth
    diskUsage
    systemMonitor
    networkSettings
    powerSettings
    sensorViewer

    # Additional tools for enhanced functionality
    baobab
    networkmanagerapplet
    blueman
    nvtopPackages.full
    mission-center
    btop
    lm_sensors
    ethtool
    iw
    mesa-demos

    # Portal packages
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
  ];

  programs.waybar = {
    enable = true;
    package = pkgs.waybar;

    settings = [
    # External monitor configuration (DP-4) - normal size
    {
      output = "DP-4";
      layer = "top";
      position = "top";
      height = 60;
      spacing = 4;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/submap"
      ];

      modules-center = [
        "hyprland/window"
        "clock"
      ];

      modules-right = [
        "custom/gpu"
        "custom/disk"
        "idle_inhibitor"
        "mpd"
        "pulseaudio"
        "custom/network"
        "bluetooth"
        "memory"
        "cpu"
        "temperature"
        "custom/battery"
        "tray"
        "custom/notification"
        "custom/power"
      ];

      # Enhanced workspaces with better visual feedback
      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = false;
        warp-on-scroll = false;
        format = "{name}";
        persistent-workspaces = {
          "1" = [];
          "2" = [];
          "3" = [];
          "4" = [];
          "5" = [];
          "6" = [];
          "7" = [];
          "8" = [];
        };
        on-click = "activate";
        on-scroll-up = "hyprctl dispatch workspace e+1";
        on-scroll-down = "hyprctl dispatch workspace e-1";
      };

      # Show current submap (resize mode, etc.)
      "hyprland/submap" = {
        format = "✨ {}";
        max-length = 8;
        tooltip = false;
      };

      "hyprland/window" = {
        format = "{title}";
        max-length = 50;
        separate-outputs = true;
        rewrite = {
          "(.*) — Mozilla Firefox" = "🌍 $1";
          "(.*) - Google Chrome" = "🌍 $1";
          "(.*) - Chromium" = "🌍 $1";
          "(.*) - Visual Studio Code" = "💻 $1";
          "(.*) - nvim" = "📝 $1";
        };
      };

      # Enhanced MPD with better controls
      mpd = {
        format = "{stateIcon} {artist} - {title}";
        format-disconnected = "󰝛";
        format-stopped = "󰓛";
        unknown-tag = "N/A";
        interval = 2;
        consume-icons = {
          on = " ";
        };
        random-icons = {
          off = "<span color=\"#f53c3c\"></span> ";
          on = " ";
        };
        repeat-icons = {
          on = " ";
        };
        single-icons = {
          on = "1 ";
        };
        state-icons = {
          paused = "";
          playing = "";
        };
        tooltip-format = "MPD (connected)";
        tooltip-format-disconnected = "MPD (disconnected)";
        on-click = "mpc toggle";
        on-click-right = "mpc next";
        on-click-middle = "mpc prev";
        on-scroll-up = "mpc volume +2";
        on-scroll-down = "mpc volume -2";
      };

      tray = {
        spacing = 10;
        icon-size = 18;
      };

      # Enhanced clock with multiple formats
      clock = {
        interval = 1;
        format = "{:%H:%M:%S}";
        format-alt = "{:%Y-%m-%d %H:%M:%S}";
        tooltip = false;
      };

      # Custom modules for system scripts
      "custom/gpu" = {
        format = "{}";
        exec = "${gpuStatus}/bin/gpu-status";
        return-type = "json";
        interval = 5;
        on-click = "gpu-toggle";
        on-click-right = "gpu-menu";
      };

      "custom/disk" = {
        format = "󰋊 {}%";
        exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'";
        interval = 30;
        tooltip = true;
        on-click = "disk-usage-gui";
      };

      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰛨";
          deactivated = "󰛧";
        };
        tooltip = true;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-bluetooth = "{icon} {volume}%";
        format-muted = "󰝟";
        format-icons = {
          default = ["󰕿" "󰖀" "󰖁"];
        };
        on-click = "pavucontrol";
        on-scroll-up = "pulsemixer --change-volume +5";
        on-scroll-down = "pulsemixer --change-volume -5";
        tooltip = true;
      };

      "custom/network" = {
        format = "{}";
        exec = "${networkStatus}/bin/network-status";
        return-type = "json";
        interval = 5;
        on-click = "network-settings";
      };

      bluetooth = {
        format = "{icon}";
        format-icons = {
          enabled = "󰂯";
          disabled = "󰂲";
        };
        format-connected = "󰂱 {num_connections}";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        on-click = "blueman-manager";
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 5;
        tooltip = true;
        on-click = "system-monitor";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 5;
        tooltip = true;
        on-click = "system-monitor";
      };

      temperature = {
        hwmon-path = "/sys/class/hwmon/hwmon6/temp1_input";
        critical-threshold = 80;
        format = "󰔏 {temperatureC}°C";
        interval = 5;
        tooltip = true;
        on-click = "sensor-viewer";
      };

      "custom/battery" = {
        format = "{}";
        exec = "${batteryHealth}/bin/battery-health";
        return-type = "json";
        interval = 5;
        tooltip = true;
        on-click = "power-settings";
      };

      "custom/notification" = {
        format = "󰂚";
        exec = "echo '󰂚'";
        interval = 30;
        tooltip = "Notifications";
        on-click = "notify-send 'Notifications' 'No notification center configured'";
      };

      "custom/power" = {
        format = "󰐥";
        tooltip = "Shutdown";
        on-click = "wlogout";
      };
    }
    # Laptop monitor configuration (eDP-1) - larger size
    {
      output = "eDP-1";
      layer = "top";
      position = "top";
      height = 80;  # Larger for laptop screen
      spacing = 6;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/submap"
      ];

      modules-center = [
        "hyprland/window"
        "clock"
      ];

      modules-right = [
        "custom/gpu"
        "custom/disk"
        "idle_inhibitor"
        "mpd"
        "pulseaudio"
        "custom/network"
        "bluetooth"
        "memory"
        "cpu"
        "temperature"
        "custom/battery"
        "tray"
        "custom/notification"
        "custom/power"
      ];

      # Copy all the module configurations from the first config
      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = false;
        warp-on-scroll = false;
        format = "{name}";
        persistent-workspaces = {
          "1" = [];
          "2" = [];
          "3" = [];
          "4" = [];
          "5" = [];
          "6" = [];
          "7" = [];
          "8" = [];
        };
        on-click = "activate";
        on-scroll-up = "hyprctl dispatch workspace e+1";
        on-scroll-down = "hyprctl dispatch workspace e-1";
      };

      "hyprland/submap" = {
        format = "✨ {}";
        max-length = 8;
        tooltip = false;
      };

      "hyprland/window" = {
        format = "{title}";
        max-length = 50;
        separate-outputs = true;
        rewrite = {
          "(.*) — Mozilla Firefox" = "🌍 $1";
          "(.*) - Google Chrome" = "🌍 $1";
          "(.*) - Chromium" = "🌍 $1";
          "(.*) - Visual Studio Code" = "💻 $1";
          "(.*) - nvim" = "📝 $1";
        };
      };

      mpd = {
        format = "{stateIcon} {artist} - {title}";
        format-disconnected = "󰝛";
        format-stopped = "󰓛";
        unknown-tag = "N/A";
        interval = 2;
        consume-icons = {
          on = " ";
        };
        random-icons = {
          off = "<span color=\"#f53c3c\"></span> ";
          on = " ";
        };
        repeat-icons = {
          on = " ";
        };
        single-icons = {
          on = "1 ";
        };
        state-icons = {
          paused = "";
          playing = "";
        };
        tooltip-format = "MPD (connected)";
        tooltip-format-disconnected = "MPD (disconnected)";
        on-click = "mpc toggle";
        on-click-right = "mpc next";
        on-click-middle = "mpc prev";
        on-scroll-up = "mpc volume +2";
        on-scroll-down = "mpc volume -2";
      };

      tray = {
        spacing = 12;  # Slightly larger spacing for laptop
        icon-size = 20;  # Slightly larger icons for laptop
      };

      clock = {
        interval = 1;
        format = "{:%H:%M:%S}";
        format-alt = "{:%Y-%m-%d %H:%M:%S}";
        tooltip = false;
      };

      "custom/gpu" = {
        format = "{}";
        exec = "${gpuStatus}/bin/gpu-status";
        return-type = "json";
        interval = 5;
        on-click = "gpu-toggle";
        on-click-right = "gpu-menu";
      };

      "custom/disk" = {
        format = "󰋊 {}%";
        exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'";
        interval = 30;
        tooltip = true;
        on-click = "disk-usage-gui";
      };

      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "󰛨";
          deactivated = "󰛧";
        };
        tooltip = true;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-bluetooth = "{icon} {volume}%";
        format-muted = "󰝟";
        format-icons = {
          default = ["󰕿" "󰖀" "󰖁"];
        };
        on-click = "pavucontrol";
        on-scroll-up = "pulsemixer --change-volume +5";
        on-scroll-down = "pulsemixer --change-volume -5";
        tooltip = true;
      };

      "custom/network" = {
        format = "{}";
        exec = "${networkStatus}/bin/network-status";
        return-type = "json";
        interval = 5;
        on-click = "network-settings";
      };

      bluetooth = {
        format = "{icon}";
        format-icons = {
          enabled = "󰂯";
          disabled = "󰂲";
        };
        format-connected = "󰂱 {num_connections}";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        on-click = "blueman-manager";
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 5;
        tooltip = true;
        on-click = "system-monitor";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 5;
        tooltip = true;
        on-click = "system-monitor";
      };

      temperature = {
        hwmon-path = "/sys/class/hwmon/hwmon6/temp1_input";
        critical-threshold = 80;
        format = "󰔏 {temperatureC}°C";
        interval = 5;
        tooltip = true;
        on-click = "sensor-viewer";
      };

      "custom/battery" = {
        format = "{}";
        exec = "${batteryHealth}/bin/battery-health";
        return-type = "json";
        interval = 5;
        tooltip = true;
        on-click = "power-settings";
      };

      "custom/notification" = {
        format = "󰂚";
        exec = "echo '󰂚'";
        interval = 30;
        tooltip = "Notifications";
        on-click = "notify-send 'Notifications' 'No notification center configured'";
      };

      "custom/power" = {
        format = "󰐥";
        tooltip = "Shutdown";
        on-click = "wlogout";
      };
    }];

    style = ''
      /* Waybar styles using deep-nord colors */
      @define-color background ${colors.background};
      @define-color foreground ${colors.foreground};
      @define-color accent ${colors.css.accent};
      @define-color warning ${colors.css.warning};
      @define-color error ${colors.css.error};
      @define-color success ${colors.css.success};
      @define-color info ${colors.css.info};

      * {
        border-radius: 0px;
        font-family: "Fira Sans", sans-serif;
        font-size: 14px;
      }

      /* Larger font size for laptop monitor */
      window#waybar.eDP-1 * {
        font-size: 18px;
      }

      window#waybar {
        background-color: @background;
        color: @foreground;
      }

      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: @foreground;
        border-bottom: 2px solid transparent;
      }

      #workspaces button.active {
        color: @accent;
        border-bottom: 2px solid @accent;
      }

      #workspaces button.urgent {
        color: @error;
        border-bottom: 2px solid @error;
      }

      #mode {
        background-color: @accent;
        color: @background;
        border-radius: 5px;
        padding: 0 10px;
        margin: 0 5px;
      }

      #window {
        padding: 0 10px;
      }

      #cpu,
      #memory,
      #temperature,
      #disk,
      #network,
      #pulseaudio,
      #battery,
      #clock,
      #custom-gpu,
      #idle_inhibitor,
      #mpd,
      #tray,
      #custom-notification,
      #custom-power {
        padding: 0 10px;
        margin: 0 5px;
        color: @foreground;
      }

      #cpu {
        background-color: @color14;
      }

      #memory {
        background-color: @color13;
      }

      #temperature {
        background-color: @color12;
      }

      #disk {
        background-color: @color11;
      }

      #network {
        background-color: @color10;
      }

      #pulseaudio {
        background-color: @color9;
      }

      #battery {
        background-color: @color8;
      }

      #clock {
        background-color: @color7;
      }

      #custom-gpu {
        background-color: @color6;
      }

      #idle_inhibitor {
        background-color: @color5;
      }

      #mpd {
        background-color: @color4;
      }

      #tray {
        background-color: @color3;
      }

      #custom-notification {
        background-color: @color2;
      }

      #custom-power {
        background-color: @color1;
      }

      /* Specific styles for custom modules based on their class */
      .intel {
        color: @color4;
      }

      .nvidia {
        color: @color2;
      }

      .performance {
        color: @color1;
      }

      .disconnected {
        color: @error;
      }

      .excellent {
        color: @success;
      }

      .good {
        color: @info;
      }

      .fair {
        color: @warning;
      }

      .poor {
        color: @error;
      }

      .charging {
        color: @success;
      }

      .full {
        color: @success;
      }

      .high {
        color: @info;
      }

      .medium {
        color: @warning;
      }

      .low {
        color: @error;
      }

      .critical {
        color: @error;
      }
    '';
  };
}


