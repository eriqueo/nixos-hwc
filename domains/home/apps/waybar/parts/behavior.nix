# Waybar Part: Behavior
# Defines the module layout and configuration for each bar instance.
{ lib, pkgs, ... }:

let
  # Define shared module lists and configurations
  commonModules = {
    modules-left = [ "hyprland/workspaces" "hyprland/submap" ];
    modules-center = [ "hyprland/window" "clock" ];
    modules-right = [
      "custom/gpu" "custom/ollama" "idle_inhibitor" "mpd" "pulseaudio"
      "custom/network" "bluetooth" "custom/disk-space"  
      "temperature" "custom/battery"  "tray" "custom/notification" "custom/power"
    ];
  };

  # Define shared widget configurations
  commonWidgets = {
    "hyprland/workspaces" = {
      disable-scroll = true;
      all-outputs = false;
      warp-on-scroll = false;
      format = "{name}";
      persistent-workspaces = {
        "1" = []; "2" = []; "3" = []; "4" = [];
        "5" = []; "6" = []; "7" = []; "8" = [];
      };
      on-click = "activate";
      on-scroll-up = "hyprctl dispatch workspace e+1";
      on-scroll-down = "hyprctl dispatch workspace e-1";
    };

    "hyprland/submap" = { format = "✨ {}"; max-length = 8; tooltip = false; };
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
      state-icons = { paused = ""; playing = ""; };
      on-click = "mpc toggle";
      on-click-right = "mpc next";
    };

    clock = { format = "{:%H:%M:%S}"; format-alt = "{:%Y-%m-%d %H:%M:%S}"; };

    "custom/gpu" = { format = "{}"; exec = "gpu-status"; return-type = "json"; interval = 5; on-click = "gpu-toggle"; };
    "custom/ollama" = { format = "{}"; exec = "waybar-ollama-status"; return-type = "json"; interval = 5; on-click = "waybar-ollama-toggle"; };
    idle_inhibitor = { format = "{icon}"; format-icons = { activated = "󰛨"; deactivated = "󰛧"; }; };
    pulseaudio = { format = "{icon} {volume}%"; format-muted = "󰝟"; format-icons = { default = ["󰕿" "󰖀" "󰖁"]; }; on-click = "pavucontrol"; };
    "custom/network" = { format = "{}"; exec = "waybar-network-status"; return-type = "json"; interval = 5; on-click = "waybar-network-settings"; };
    bluetooth = { format = "{icon}"; format-icons = { enabled = "󰂯"; disabled = "󰂲"; }; format-connected = "󰂱 {num_connections}"; on-click = "blueman-manager"; };
    temperature = {
      # Use coretemp device for accurate CPU package temperature
      # hwmon-path-abs points to device hwmon directory (not hwmon/hwmonN subdirectory)
      hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
      input-filename = "temp1_input";
      critical-threshold = 80;
      format = "󰔏 {temperatureC}°C";
      format-critical = "󰔏 {temperatureC}°C";
    };
    "custom/power-profile" = { format = "{}"; exec = "waybar-power-profile"; return-type = "json"; interval = 10; on-click = "waybar-power-profile-toggle"; };
    "custom/disk-space" = { format = "{}"; exec = "waybar-disk-space"; return-type = "json"; interval = 30; on-click = "baobab"; };
    "custom/battery" = { format = "{}"; exec = "waybar-battery-health"; return-type = "json"; interval = 5; on-click = "waybar-power-settings"; };
    "custom/notification" = { format = "󰂚"; tooltip = "Notifications"; on-click = "swaync-client -t -sw"; };
    "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };
  };

  # External monitor base configuration
  externalConfig = {
    name = "external";
    # Match any non-laptop display (handles DP/HDMI/USB-C docks); if none present, Waybar skips this bar.
    output = [ "^(DP|HDMI|DVI|USB-C|Virtual).*" ];
    layer = "top";
    position = "top";
    height = 60;
    spacing = 4;
    tray = { spacing = 10; icon-size = 18; };
  };

in
[
  # External monitor(s) - merge base config with modules and widgets
  (externalConfig // commonModules // commonWidgets)

  # Laptop monitor (eDP-*) - explicitly define with same modules but different sizing
  ({
    name = "internal";
    output = "eDP-*";
    layer = "top";
    position = "top";
    height = 80;  # Larger for laptop screen
    spacing = 6;
    tray = { spacing = 12; icon-size = 20; };  # Override for laptop
  } // commonModules // commonWidgets)
]
