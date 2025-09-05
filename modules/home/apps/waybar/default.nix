# nixos-hwc/modules/home/waybar/default.nix
#
# WAYBAR - Wayland status bar configuration (Complete UI restoration)
# Preserves 100% functionality from /etc/nixos/hosts/laptop/modules/waybar.nix monolith
#
# DEPENDENCIES (Upstream):
#   - modules/infrastructure/waybar-hardware-tools.nix (provides all 13 tools)
#   - Home-Manager programs.waybar support
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports via home-manager)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/home/waybar/default.nix
#
# USAGE:
#   home-manager.users.<name>.imports = [ ../modules/home/waybar/default.nix ];

{ config, lib, pkgs, nixosConfig, ... }:

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
in {

  #============================================================================
  # VALIDATION - Assertions and checks
  #============================================================================
  # Note: Runtime assertions deferred to avoid build-time path dependencies

  #============================================================================
  # IMPLEMENTATION - Complete Waybar Configuration (Verbatim from Monolith)
  #============================================================================
  
  # Enhanced dependencies
  home.packages = with pkgs; [
    pavucontrol
    swaynotificationcenter
    wlogout

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
        exec = "waybar-gpu-status";
        return-type = "json";
        interval = 5;
        on-click = "waybar-gpu-toggle";
        on-click-right = "waybar-gpu-menu";
      };

      "custom/disk" = {
        format = "󰋊 {}%";
        exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'";
        interval = 30;
        tooltip = true;
        on-click = "waybar-disk-usage-gui";
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
        exec = "waybar-network-status";
        return-type = "json";
        interval = 5;
        on-click = "waybar-network-settings";
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
        on-click = "waybar-system-monitor";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 5;
        tooltip = true;
        on-click = "waybar-system-monitor";
      };

      temperature = {
        hwmon-path = "/sys/class/hwmon/hwmon6/temp1_input";
        critical-threshold = 80;
        format = "󰔏 {temperatureC}°C";
        interval = 5;
        tooltip = true;
        on-click = "waybar-sensor-viewer";
      };

      "custom/battery" = {
        format = "{}";
        exec = "waybar-battery-health";
        return-type = "json";
        interval = 5;
        tooltip = true;
        on-click = "waybar-power-settings";
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
        exec = "waybar-gpu-status";
        return-type = "json";
        interval = 5;
        on-click = "waybar-gpu-toggle";
        on-click-right = "waybar-gpu-menu";
      };

      "custom/disk" = {
        format = "󰋊 {}%";
        exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'";
        interval = 30;
        tooltip = true;
        on-click = "waybar-disk-usage-gui";
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
        exec = "waybar-network-status";
        return-type = "json";
        interval = 5;
        on-click = "waybar-network-settings";
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
        on-click = "waybar-system-monitor";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 5;
        tooltip = true;
        on-click = "waybar-system-monitor";
      };

      temperature = {
        hwmon-path = "/sys/class/hwmon/hwmon6/temp1_input";
        critical-threshold = 80;
        format = "󰔏 {temperatureC}°C";
        interval = 5;
        tooltip = true;
        on-click = "waybar-sensor-viewer";
      };

      "custom/battery" = {
        format = "{}";
        exec = "waybar-battery-health";
        return-type = "json";
        interval = 5;
        tooltip = true;
        on-click = "waybar-power-settings";
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