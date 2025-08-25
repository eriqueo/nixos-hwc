{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.desktop.waybar;
  
  # Enhanced network status
  networkStatus = pkgs.writeScriptBin "network-status" ''
    #!/usr/bin/env bash
    ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | head -1)
    if [[ -z "$ACTIVE_CONN" ]]; then
      echo "{\"text\": \"󰤭\", \"class\": \"disconnected\", \"tooltip\": \"No network connection\"}"
      exit 0
    fi
    CONN_NAME=$(echo "$ACTIVE_CONN" | cut -d: -f1)
    CONN_TYPE=$(echo "$ACTIVE_CONN" | cut -d: -f2)
    DEVICE=$(echo "$ACTIVE_CONN" | cut -d: -f3)
    if [[ "$CONN_TYPE" == "wifi" ]]; then
      SIGNAL=$(nmcli -f IN-USE,SIGNAL dev wifi | grep "^\*" | awk '{print $2}')
      SPEED=$(iw dev "$DEVICE" link 2>/dev/null | grep "tx bitrate" | awk '{print $3 " " $4}' || echo "Unknown")
      if [[ $SIGNAL -gt 75 ]]; then
        ICON="󰤨"; CLASS="excellent"
      elif [[ $SIGNAL -gt 50 ]]; then
        ICON="󰤥"; CLASS="good"
      elif [[ $SIGNAL -gt 25 ]]; then
        ICON="󰤢"; CLASS="fair"
      else
        ICON="󰤟"; CLASS="poor"
      fi
      TOOLTIP="WiFi: $CONN_NAME\\nSignal: $SIGNAL%\\nSpeed: $SPEED"
    else
      ICON="󰈀"; CLASS="ethernet"
      SPEED=$(ethtool "$DEVICE" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
      TOOLTIP="Ethernet: $CONN_NAME\\nSpeed: $SPEED"
    fi
    echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
  '';

  # Battery health monitor
  batteryHealth = pkgs.writeScriptBin "battery-health" ''
    #!/usr/bin/env bash
    BATTERY_PATH="/sys/class/power_supply/BAT0"
    if [[ ! -d "$BATTERY_PATH" ]]; then
      echo "{\"text\": \"󰂑\", \"tooltip\": \"No battery detected\"}"
      exit 0
    fi
    CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
    STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
    HEALTH=$(cat "$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
    CYCLE_COUNT=$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")
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
    if [[ "$STATUS" == "Charging" ]]; then
      ICON="󰂄"; CLASS="charging"
    elif [[ $CAPACITY -gt 90 ]]; then
      ICON="󰁹"; CLASS="full"
    elif [[ $CAPACITY -gt 75 ]]; then
      ICON="󰂂"; CLASS="high"
    elif [[ $CAPACITY -gt 50 ]]; then
      ICON="󰁿"; CLASS="medium"
    elif [[ $CAPACITY -gt 25 ]]; then
      ICON="󰁼"; CLASS="low"
    else
      ICON="󰁺"; CLASS="critical"
    fi
    TOOLTIP="Battery: $CAPACITY%\\nStatus: $STATUS\\nHealth: $HEALTH\\nCycles: $CYCLE_COUNT\\nTime: $TIME_STR"
    echo "{\"text\": \"$ICON $CAPACITY%\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
  '';

  # GPU menu
  gpuMenu = pkgs.writeScriptBin "gpu-menu" ''
    #!/usr/bin/env bash
    CHOICE=$(echo -e "Launch next app with NVIDIA\\nView GPU usage\\nOpen nvidia-settings\\nToggle Performance Mode" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "GPU Options:")
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
  diskUsage = pkgs.writeScriptBin "disk-usage-gui" ''#!/usr/bin/env bash
    ${pkgs.baobab}/bin/baobab &
  '';

  systemMonitor = pkgs.writeScriptBin "system-monitor" ''#!/usr/bin/env bash
    ${pkgs.kitty}/bin/kitty --title "System Monitor" -e ${pkgs.btop}/bin/btop &
  '';

  networkSettings = pkgs.writeScriptBin "network-settings" ''#!/usr/bin/env bash
    ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
  '';

  powerSettings = pkgs.writeScriptBin "power-settings" ''#!/usr/bin/env bash
    if command -v gnome-power-statistics >/dev/null 2>&1; then
      gnome-power-statistics &
    elif command -v xfce4-power-manager-settings >/dev/null 2>&1; then
      xfce4-power-manager-settings &
    else
      ${pkgs.kitty}/bin/kitty --title "Power Info" -e sh -c "${pkgs.acpi}/bin/acpi -V && ${pkgs.powertop}/bin/powertop --dump && read" &
    fi
  '';

  sensorViewer = pkgs.writeScriptBin "sensor-viewer" ''#!/usr/bin/env bash
    if command -v mission-center >/dev/null 2>&1; then
      mission-center &
    else
      ${pkgs.kitty}/bin/kitty --title "Sensors" -e sh -c "${pkgs.lm_sensors}/bin/sensors && read" &
    fi
  '';

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
in {
  options.hwc.desktop.waybar = {
    enable = lib.mkEnableOption "Waybar status bar";

    position = lib.mkOption {
      type = lib.types.enum [ "top" "bottom" ];
      default = "top";
      description = "Waybar position";
    };

    height = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Waybar height";
    };

    modules = {
      showWorkspaces = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show workspace switcher";
      };
      showNetwork = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show network module";
      };
      showBattery = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show battery module";
      };
      showGpuStatus = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show GPU status and controls";
      };
      showSystemMonitor = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show system monitoring (CPU, memory, temp)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
        # Core waybar tools
        pavucontrol
        swaynotificationcenter  
        wlogout

        # Enhanced waybar scripts
        networkStatus
        batteryHealth
        gpuMenu
        diskUsage
        systemMonitor
        networkSettings
        powerSettings
        sensorViewer

        # Additional tools for enhanced functionality
        baobab
        networkmanagerapplet
        nvtopPackages.full
        mission-center
        btop
        lm_sensors
        ethtool
        iw
        mesa-demos
        mpc-cli

        # Portal packages
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];

    # Configure waybar through home-manager
    programs.waybar = {
      enable = true;
      
      settings = [{
        layer = "top";
        position = cfg.position;
        height = cfg.height;
        spacing = 4;

        modules-left = [ "hyprland/workspaces" "hyprland/submap" ];
        modules-center = [ "hyprland/window" "clock" ];
        modules-right = [
          "custom/gpu"
          "custom/disk"
          "idle_inhibitor"
          "mpd"
          "pulseaudio"
          "custom/network"
          "memory"
          "cpu"
          "temperature"
          "custom/battery"
          "tray"
          "custom/notification"
          "custom/power"
        ];

        "hyprland/workspaces" = lib.mkIf cfg.modules.showWorkspaces {
          disable-scroll = true;
          all-outputs = false;
          warp-on-scroll = false;
          format = "{icon}";
          format-icons = {
            "1" = "󰈹"; "2" = "󰭹"; "3" = "󰏘"; "4" = "󰎞";
            "5" = "󰕧"; "6" = "󰊢"; "7" = "󰋩"; "8" = "󰚌";
            "11" = "󰈹"; "12" = "󰭹"; "13" = "󰏘"; "14" = "󰎞"; 
            "15" = "󰕧"; "16" = "󰊢"; "17" = "󰋩"; "18" = "󰚌";
            active = "";
            default = "";
            urgent = "";
          };
          persistent-workspaces = {
            "1" = []; "2" = []; "3" = []; "4" = [];
            "5" = []; "6" = []; "7" = []; "8" = [];
          };
          on-click = "activate";
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

        clock = {
          interval = 1;
          format = "{:%H:%M:%S}";
          format-alt = "{:%Y-%m-%d %H:%M:%S}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
        };

        "custom/gpu" = {
          format = "{}";
          exec = "gpu-status";
          return-type = "json";
          interval = 5;
          on-click = "gpu-toggle";
          on-click-right = "gpu-menu";
        };

        "custom/disk" = {
          format = "󰋊 {percentage_used}%";
          exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'";
          interval = 30;
          tooltip = true;
          on-click = "disk-usage-gui";
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
          exec = "network-status";
          return-type = "json";
          interval = 5;
          on-click = "network-settings";
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
          thermal-zone = 0;
          hwmon-path = "/sys/class/hwmon/hwmon2/temp1_input";
          critical-threshold = 80;
          format = "󰔏 {temperature}°C";
          interval = 5;
          tooltip = true;
          on-click = "sensor-viewer";
        };

        "custom/battery" = {
          format = "{}";
          exec = "battery-health";
          return-type = "json";
          interval = 5;
          tooltip = true;
          on-click = "power-settings";
        };

        tray = {
          spacing = 10;
          icon-size = 18;
        };

        "custom/notification" = {
          format = "{icon}";
          exec = "swaynotificationcenter-client -c count";
          interval = 1;
          tooltip = true;
          on-click = "swaynotificationcenter-client -t";
          format-icons = {
            "default" = "󰂚";
            "0" = "󰂛";
          };
        };

        "custom/power" = {
          format = "󰐥";
          tooltip = "Shutdown";
          on-click = "wlogout";
        };
      }];

      style = ''
        /* Waybar styles using Gruvbox Material colors */
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

        #clock,
        #battery,
        #cpu,
        #memory,
        #temperature,
        #network,
        #pulseaudio,
        #custom-gpu,
        #idle_inhibitor,
        #tray,
        #custom-notification,
        #custom-power {
          padding: 0 10px;
          margin: 0 5px;
          color: @foreground;
        }

        /* Specific styles for custom modules based on their class */
        .intel {
          color: ${colors.color4};
        }

        .nvidia {
          color: ${colors.color2};
        }

        .performance {
          color: ${colors.color1};
        }

        #battery.charging {
          color: @success;
        }

        #battery.critical:not(.charging) {
          color: @error;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          animation-direction: alternate;
        }
      '';
    };
  };
}
