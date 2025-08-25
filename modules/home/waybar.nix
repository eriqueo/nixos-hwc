{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.desktop.waybar;
  
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
    # Waybar requires both system packages and home-manager configuration
    environment.systemPackages = with pkgs; [
      waybar
      pavucontrol
      swaynotificationcenter
      wlogout
      baobab
      networkmanagerapplet
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
      # GPU toggle script
      (writeScriptBin "gpu-toggle" ''
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
      '')

      # GPU status script  
      (writeScriptBin "gpu-status" ''
        #!/usr/bin/env bash
        GPU_MODE_FILE="/tmp/gpu-mode"
        DEFAULT_MODE="intel"

        if [[ ! -f "$GPU_MODE_FILE" ]]; then
          echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
        fi

        CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
        CURRENT_GPU=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
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
            TOOLTIP="NVIDIA Mode: $CURRENT_GPU\\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C"
            ;;
          "performance")
            ICON="⚡"
            CLASS="performance"
            TOOLTIP="Performance Mode: Auto-GPU Selection\\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C"
            ;;
          *)
            ICON="󰢮"
            CLASS="intel"
            TOOLTIP="Intel Mode (Default): $CURRENT_GPU"
            ;;
        esac

        echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
      '')
    ];

    # Configure waybar through home-manager
    home-manager.users.eric.programs.waybar = {
      enable = true;
      
      settings = [{
        layer = "top";
        position = cfg.position;
        height = cfg.height;
        spacing = 4;

        modules-left = [ "hyprland/workspaces" "hyprland/submap" ];
        modules-center = [ "hyprland/window" "clock" ];
        modules-right = lib.optionals cfg.modules.showGpuStatus [ "custom/gpu" ] ++
                      lib.optionals cfg.modules.showSystemMonitor [ "memory" "cpu" "temperature" ] ++
                      [ "idle_inhibitor" "pulseaudio" ] ++
                      lib.optionals cfg.modules.showNetwork [ "network" ] ++
                      lib.optionals cfg.modules.showBattery [ "battery" ] ++
                      [ "tray" "custom/notification" "custom/power" ];

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

        "custom/gpu" = lib.mkIf cfg.modules.showGpuStatus {
          format = "{}";
          exec = "gpu-status";
          return-type = "json";
          interval = 5;
          on-click = "gpu-toggle";
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

        network = lib.mkIf cfg.modules.showNetwork {
          format-wifi = "󰤨 {signalStrength}%";
          format-ethernet = "󰈀";
          format-disconnected = "󰤭";
          tooltip-format-wifi = "WiFi: {essid}\\nSignal: {signalStrength}%";
          tooltip-format-ethernet = "Ethernet: {ifname}";
          tooltip-format-disconnected = "Disconnected";
        };

        memory = lib.mkIf cfg.modules.showSystemMonitor {
          format = "󰍛 {percentage}%";
          interval = 5;
          tooltip = true;
        };

        cpu = lib.mkIf cfg.modules.showSystemMonitor {
          format = "󰻠 {usage}%";
          interval = 5;
          tooltip = true;
        };

        temperature = lib.mkIf cfg.modules.showSystemMonitor {
          thermal-zone = 0;
          hwmon-path = "/sys/class/hwmon/hwmon2/temp1_input";
          critical-threshold = 80;
          format = "󰔏 {temperatureC}°C";
          interval = 5;
          tooltip = true;
        };

        battery = lib.mkIf cfg.modules.showBattery {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-charging = "{capacity}% 󰂄";
          format-plugged = "{capacity}% ";
          format-alt = "{time} {icon}";
          format-icons = [ "󰁺" "󰁼" "󰁿" "󰂂" "󰁹" ];
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
