{ config, lib, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    package = pkgs.waybar;

    settings = [
      # External monitor (DP-4)
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
            "(.*) - Google Chrome"   = "🌍 $1";
            "(.*) - Chromium"        = "🌍 $1";
            "(.*) - Visual Studio Code" = "💻 $1";
            "(.*) - nvim"            = "📝 $1";
          };
        };

        mpd = {
          format = "{stateIcon} {artist} - {title}";
          format-disconnected = "󰝛";
          format-stopped = "󰓛";
          unknown-tag = "N/A";
          interval = 2;
          consume-icons.on = " ";
          random-icons = { off = "<span color=\"#f53c3c\"></span> "; on = " "; };
          repeat-icons.on = " ";
          single-icons.on = "1 ";
          state-icons = { paused = ""; playing = ""; };
          tooltip-format = "MPD (connected)";
          tooltip-format-disconnected = "MPD (disconnected)";
          on-click = "mpc toggle";
          on-click-right = "mpc next";
          on-click-middle = "mpc prev";
          on-scroll-up = "mpc volume +2";
          on-scroll-down = "mpc volume -2";
        };

        tray = { spacing = 10; icon-size = 18; };

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
          format-icons = { activated = "󰛨"; deactivated = "󰛧"; };
          tooltip = true;
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-bluetooth = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons.default = [ "󰕿" "󰖀" "󰖁" ];
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
          format-icons = { enabled = "󰂯"; disabled = "󰂲"; };
          format-connected = "󰂱 {num_connections}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected =
            "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "blueman-manager";
        };

        memory = { format = "󰍛 {percentage}%"; interval = 5; tooltip = true; on-click = "waybar-system-monitor"; };
        cpu    = { format = "󰻠 {usage}%";       interval = 5; tooltip = true; on-click = "waybar-system-monitor"; };

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

        "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };
      }

      # Laptop monitor (eDP-1)
      {
        output = "eDP-1";
        layer = "top";
        position = "top";
        height = 80;
        spacing = 6;

        modules-left   = [ "hyprland/workspaces" "hyprland/submap" ];
        modules-center = [ "hyprland/window" "clock" ];
        modules-right  = [
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
            "(.*) - Google Chrome"   = "🌍 $1";
            "(.*) - Chromium"        = "🌍 $1";
            "(.*) - Visual Studio Code" = "💻 $1";
            "(.*) - nvim"            = "📝 $1";
          };
        };

        mpd = {
          format = "{stateIcon} {artist} - {title}";
          format-disconnected = "󰝛";
          format-stopped = "󰓛";
          unknown-tag = "N/A";
          interval = 2;
          consume-icons.on = " ";
          random-icons = { off = "<span color=\"#f53c3c\"></span> "; on = " "; };
          repeat-icons.on = " ";
          single-icons.on = "1 ";
          state-icons = { paused = ""; playing = ""; };
          tooltip-format = "MPD (connected)";
          tooltip-format-disconnected = "MPD (disconnected)";
          on-click = "mpc toggle";
          on-click-right = "mpc next";
          on-click-middle = "mpc prev";
          on-scroll-up = "mpc volume +2";
          on-scroll-down = "mpc volume -2";
        };

        tray = { spacing = 12; icon-size = 20; };

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
          format-icons = { activated = "󰛨"; deactivated = "󰛧"; };
          tooltip = true;
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-bluetooth = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons.default = [ "󰕿" "󰖀" "󰖁" ];
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
          format-icons = { enabled = "󰂯"; disabled = "󰂲"; };
          format-connected = "󰂱 {num_connections}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected =
            "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "blueman-manager";
        };

        memory = { format = "󰍛 {percentage}%"; interval = 5; tooltip = true; on-click = "waybar-system-monitor"; };
        cpu    = { format = "󰻠 {usage}%";       interval = 5; tooltip = true; on-click = "waybar-system-monitor"; };

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

        "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };
      }
    ];
  };

 xdg.configFile."waybar/style.css".text = config.hwc.home.theme.adapters.waybar.css + ''
   /* Overrides that rely on GTK @define-color tokens */
   window#waybar.eDP-1 * { font-size: 18px; }

   window#waybar {
     background-color: @bg;
     color: @fg;
   }

   #workspaces button {
     padding: 0 5px;
     background-color: transparent;
     color: @fg;
     border-bottom: 2px solid transparent;
   }
   #workspaces button.active {
     color: @accent;
     border-bottom: 2px solid @accent;
   }
   #workspaces button.urgent {
     color: @crit;
     border-bottom: 2px solid @crit;
   }

   #mode {
     background-color: @accent;
     color: @bg;
     border-radius: 5px;
     padding: 0 10px;
     margin: 0 5px;
   }

   #window { padding: 0 10px; }

   /* Common module paddings */
   #cpu, #memory, #temperature, #disk, #network, #pulseaudio, #battery,
   #clock, #custom-gpu, #idle_inhibitor, #mpd, #tray, #custom-notification, #custom-power {
     padding: 0 10px;
     margin: 0 5px;
     color: @fg;
   }

   /* Optional tints using palette tokens */
   #pulseaudio            { background-color: @accentAlt; }
   #custom-notification   { background-color: @warn; }
   #custom-power          { background-color: @crit; }

   /* Classes emitted by your JSON scripts */
   .disconnected { color: @crit; }
   .excellent    { color: @good; }
   .good         { color: @good; }
   .fair         { color: @warn; }
   .poor         { color: @crit; }
   .charging     { color: @good; }
   .full         { color: @good; }
   .high         { color: @accentAlt; }
   .medium       { color: @warn; }
   .low          { color: @crit; }
   .critical     { color: @crit; }
 '';
}
