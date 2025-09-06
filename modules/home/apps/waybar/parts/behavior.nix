# Waybar Part: Behavior
# Defines the module layout and configuration for each bar instance.
{ lib, pkgs, ... }:

# The settings are a list of attribute sets, one for each monitor.
[
  # External monitor configuration (DP-4)
  {
    output = "DP-4";
    layer = "top";
    position = "top";
    height = 60;
    spacing = 4;

    modules-left = [ "hyprland/workspaces" "hyprland/submap" ];
    modules-center = [ "hyprland/window" "clock" ];
    modules-right = [
      "custom/gpu" "custom/disk" "idle_inhibitor" "mpd" "pulseaudio"
      "custom/network" "bluetooth" "memory" "cpu" "temperature"
      "custom/battery" "tray" "custom/notification" "custom/power"
    ];

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

    tray = { spacing = 10; icon-size = 18; };
    clock = { format = "{:%H:%M:%S}"; format-alt = "{:%Y-%m-%d %H:%M:%S}"; };

    "custom/gpu" = { format = "{}"; exec = "waybar-gpu-status"; return-type = "json"; interval = 5; on-click = "waybar-gpu-toggle"; };
    "custom/disk" = { format = "󰋊 {}%"; exec = "df -h / | awk 'NR==2 {print $5}' | sed 's/%//'"; interval = 30; };
    idle_inhibitor = { format = "{icon}"; format-icons = { activated = "󰛨"; deactivated = "󰛧"; }; };
    pulseaudio = { format = "{icon} {volume}%"; format-muted = "󰝟"; format-icons = { default = ["󰕿" "󰖀" "󰖁"]; }; on-click = "pavucontrol"; };
    "custom/network" = { format = "{}"; exec = "waybar-network-status"; return-type = "json"; interval = 5; on-click = "waybar-network-settings"; };
    bluetooth = { format = "{icon}"; format-icons = { enabled = "󰂯"; disabled = "󰂲"; }; format-connected = "󰂱 {num_connections}"; on-click = "blueman-manager"; };
    memory = { format = "󰍛 {percentage}%"; interval = 5; on-click = "waybar-system-monitor"; };
    cpu = { format = "󰻠 {usage}%"; interval = 5; on-click = "waybar-system-monitor"; };
    temperature = { hwmon-path = "/sys/class/hwmon/hwmon6/temp1_input"; critical-threshold = 80; format = "󰔏 {temperatureC}°C"; };
    "custom/battery" = { format = "{}"; exec = "waybar-battery-health"; return-type = "json"; interval = 5; on-click = "waybar-power-settings"; };
    "custom/notification" = { format = "󰂚"; tooltip = "Notifications"; on-click = "notify-send 'Notifications' 'No notification center configured'"; };
    "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };
  }

  # Laptop monitor configuration (eDP-1)
  {
    output = "eDP-1";
    height = 80; # Larger for laptop screen
    spacing = 6;

    # Inherit all module definitions from the first bar instance
    # This is a powerful Waybar feature to avoid duplication.
    # We only need to redefine things we want to change.
    inherit = "DP-4";

    # Example of an override for the laptop screen
    tray = { spacing = 12; icon-size = 20; };
  }
]
