# nixos-hwc/modules/home/waybar.nix
#
# Home UI: Waybar (HM consumer via NixOS orchestrator)
# NixOS options gate inclusion; Home‑Manager config lives under home-manager.users.<user>.
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports HM and sets home.stateVersion)
#   - home-manager.nixosModules.home-manager (enabled at flake/machine)
#
# USED BY (Downstream):
#   - machines/*/config.nix  (e.g., hwc.desktop.waybar.enable = true)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (or any profile that wants Waybar)
#
# USAGE:
#   hwc.desktop.waybar.enable = true;
#   # Optional:
#   #   hwc.desktop.waybar.position = "top" | "bottom";
#   #   hwc.desktop.waybar.height = 60;
#   #   hwc.desktop.waybar.modules.showNetwork = true;  # etc.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.desktop.waybar;

  # Enhanced network status
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
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$ICON" "$CLASS" "$TOOLTIP"
  '';

  # Battery health monitor
  batteryHealth = pkgs.writeShellScriptBin "battery-health" ''
    #!/usr/bin/env bash
    BATTERY_PATH="/sys/class/power_supply/BAT0"
    if [[ ! -d "$BATTERY_PATH" ]]; then
      echo '{"text":"󰂑","tooltip":"No battery detected"}'
      exit 0
    fi
    CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "0")
    STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")
    HEALTH=$(cat "$BATTERY_PATH/health" 2>/dev/null || echo "Unknown")
    CYCLE_COUNT=$(cat "$BATTERY_PATH/cycle_count" 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Discharging" ]]; then
      POWER_NOW=$(cat "$BATTERY_PATH/power_now" 2>/dev/null || echo "0")
      ENERGY_NOW=$(cat "$BATTERY_PATH/energy_now" 2>/dev/null || echo "0")
      if [[ ${POWER_NOW:-0} -gt 0 ]]; then
        # crude hours estimation; many laptops expose different units
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
    if [[ "$STATUS" == "Charging" ]]; then ICON="󰂄"; CLASS="charging"
    elif [[ ${CAPACITY:-0} -gt 90 ]]; then ICON="󰁹"; CLASS="full"
    elif [[ ${CAPACITY:-0} -gt 75 ]]; then ICON="󰂂"; CLASS="high"
    elif [[ ${CAPACITY:-0} -gt 50 ]]; then ICON="󰁿"; CLASS="medium"
    elif [[ ${CAPACITY:-0} -gt 25 ]]; then ICON="󰁼"; CLASS="low"
    else ICON="󰁺"; CLASS="critical"; fi
    TOOLTIP="Battery: ${CAPACITY:-0}%\nStatus: $STATUS\nHealth: $HEALTH\nCycles: $CYCLE_COUNT\nTime: $TIME_STR"
    printf '{"text":"%s %s%%","class":"%s","tooltip":"%s"}\n' "$ICON" "${CAPACITY:-0}" "$CLASS" "$TOOLTIP"
  '';

  # GPU menu
  gpuMenu = pkgs.writeShellScriptBin "gpu-menu" ''
    #!/usr/bin/env bash
    CHOICE=$(printf "Launch next app with NVIDIA\nView GPU usage\nOpen nvidia-settings\nToggle Performance Mode" | ${pkgs.wofi}/bin/wofi --dmenu --prompt "GPU Options:")
    case "$CHOICE" in
      "Launch next app with NVIDIA")
        touch /tmp/gpu-next-nvidia
        ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Next app will use NVIDIA 󰾲" -i gpu-card
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

  # System monitoring helpers
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

  colors = {
    background = "#282828";
    foreground = "#d4be98";
    selection_bg = "#7daea3";
    selection_fg = "#282828";
    cursor = "#d4be98";
    cursor_text = "#282828";
    url = "#7daea3";
    color0  = "#32302F"; color1  = "#ea6962"; color2  = "#a9b665"; color3  = "#d8a657";
    color4  = "#7daea3"; color5  = "#d3869b"; color6  = "#89b482"; color7  = "#d4be98";
    color8  = "#45403d"; color9  = "#ea6962"; color10 = "#a9b665"; color11 = "#d8a657";
    color12 = "#7daea3"; color13 = "#d3869b"; color14 = "#89b482"; color15 = "#d4be98";
    css = {
      background = "#282828"; foreground = "#d4be98"; accent = "#7daea3";
      warning = "#d8a657"; error = "#ea6962"; success = "#a9b665"; info = "#7daea3";
    };
  };
in
{
  #============================================================================
  # OPTIONS (NixOS layer) - feature gate and simple knobs
  #============================================================================
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

  #============================================================================
  # IMPLEMENTATION (NixOS -> HM bridge) - put HM config under users.<name>
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Make Home‑Manager use the system pkgs set (avoids duplication/mismatch).
    home-manager.useGlobalPkgs = lib.mkDefault true;

    # Wire HM config for the target user.
    home-manager.users.eric = {
      # Packages needed by Waybar modules & helper scripts
      home.packages = with pkgs; [
        pavucontrol
        swaynotificationcenter
        wlogout

        networkStatus
        batteryHealth
        gpuMenu
        diskUsage
        systemMonitor
        networkSettings
        powerSettings
        sensorViewer

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
        libnotify

        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];

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
              active = ""; default = ""; urgent = "";
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
            consume-icons = { on = " "; };
            random-icons = { off = "<span color=\"#f53c3c\"></span> "; on = " "; };
            repeat-icons = { on = " "; };
            single-icons = { on = "1 "; };
            state-icons = { paused = ""; playing = ""; };
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
            format-icons = { activated = "󰛨"; deactivated = "󰛧"; };
            tooltip = true;
          };

          pulseaudio = {
            format = "{icon} {volume}%";
            format-bluetooth = "{icon} {volume}%";
            format-muted = "󰝟";
            format-icons = { default = [ "󰕿" "󰖀" "󰖁" ]; };
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
            # If you actually use swaync, the commands are swaync-client -c / -t
            exec = "swaynotificationcenter-client -c count";
            interval = 1;
            tooltip = true;
            on-click = "swaynotificationcenter-client -t";
            format-icons = { "default" = "󰂚"; "0" = "󰂛"; };
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
          #workspaces button.active { color: @accent; border-bottom: 2px solid @accent; }
          #workspaces button.urgent { color: @error; border-bottom: 2px solid @error; }

          #clock, #battery, #cpu, #memory, #temperature, #network, #pulseaudio,
          #custom-gpu, #idle_inhibitor, #tray, #custom-notification, #custom-power {
            padding: 0 10px;
            margin: 0 5px;
            color: @foreground;
          }

          .intel { color: ${colors.color4}; }
          .nvidia { color: ${colors.color2}; }
          .performance { color: ${colors.color1}; }

          #battery.charging { color: @success; }
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
  };
}
