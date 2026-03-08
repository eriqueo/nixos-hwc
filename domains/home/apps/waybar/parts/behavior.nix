{ lib, pkgs, osConfig ? {}, ... }:

let
  commonModules = {
    modules-left = [ "hyprland/workspaces" "hyprland/submap" ];
    modules-center = [ "hyprland/window" "clock" ];
    modules-right = [
      "custom/gpu" "custom/ollama" "idle_inhibitor" "mpd"
      "group/connectivity"
      "custom/disk-space" "temperature"
      "custom/battery" "custom/proton-auth" "custom/weather"
      "tray" "custom/notification" "custom/power"
    ];
  };

  workspaceInternal = {
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

  workspaceExternal = {
    disable-scroll = true;
    all-outputs = false;
    warp-on-scroll = false;
    format = "{icon}";
    format-icons = {
      "11" = "1"; "12" = "2"; "13" = "3"; "14" = "4";
      "15" = "5"; "16" = "6"; "17" = "7"; "18" = "8";
      "default" = "•";
    };
    persistent-workspaces = {
      "11" = []; "12" = []; "13" = []; "14" = [];
      "15" = []; "16" = []; "17" = []; "18" = [];
    };
    on-click = "activate";
    on-scroll-up = "hyprctl dispatch workspace e+1";
    on-scroll-down = "hyprctl dispatch workspace e-1";
  };

  commonWidgetsBase = {
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

    clock = {
      format = "{:%b %d %I:%M %p}";           # Mar 06 02:35 PM
      format-alt = "{:%Y-%m-%d %A %I:%M %p}";
      tooltip-format = "<tt><small>{calendar}</small></tt>";
    };

    "custom/gpu" = { format = "{}"; exec = "gpu-status"; return-type = "json"; interval = 5; on-click = "gpu-toggle"; };
    "custom/ollama" = { format = "{}"; exec = "waybar-ollama-status"; return-type = "json"; interval = 5; on-click = "waybar-ollama-toggle"; };
    idle_inhibitor = { format = "{icon}"; format-icons = { activated = "󰛨"; deactivated = "󰛧"; }; };
    pulseaudio = { format = "{icon} {volume}%"; format-muted = "󰝟"; format-icons = { default = ["󰕿" "󰖀" "󰖁"]; }; on-click = "pavucontrol"; };
    "custom/network" = { format = "{}"; exec = "waybar-network-status"; return-type = "json"; interval = 5; on-click = "waybar-network-settings"; };
    bluetooth = { format = "{icon}"; format-icons = { enabled = "󰂯"; disabled = "󰂲"; }; format-connected = "󰂱 {num_connections}"; on-click = "blueman-manager"; };
    temperature = {
      hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
      input-filename = "temp1_input";
      critical-threshold = 80;
      format = "󰔏 {temperatureC}°C";
      format-critical = "󰔏 {temperatureC}°C";
    };
    "custom/power-profile" = { format = "{}"; exec = "waybar-power-profile"; return-type = "json"; interval = 10; on-click = "waybar-power-profile-toggle"; };
    "custom/disk-space" = { format = "{}"; exec = "waybar-disk-space"; return-type = "json"; interval = 30; on-click = "baobab"; };
    "custom/battery" = { format = "{}"; exec = "waybar-battery-health"; return-type = "json"; interval = 5; on-click = "waybar-power-settings"; };
    "custom/proton-auth" = { format = "󰦝"; tooltip = "Proton Authenticator (SUPER+A)"; on-click = "proton-authenticator-toggle"; };
    "custom/notification" = { format = "󰂚"; tooltip = "Notifications"; on-click = "swaync-client -t -sw"; };
    "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };

    # === NEW: Weather for Bozeman ===
    "custom/weather" = {
      format = "{}";
      exec = "waybar-weather";
      return-type = "json";
      interval = 1800;
      on-click = "kitty --single-instance --hold -e bash -c 'curl -s wttr.in/Bozeman?u && echo -e \"\\n\\n────────────────────────────\\nPress any key to close...\" && read -n 1 -s -r'";
    };
    
    # === NEW: Connectivity group (pill) — clicks still work individually ===
    "group/connectivity" = {
      orientation = "horizontal";
      modules = [ "pulseaudio" "bluetooth" "custom/network" ];
    };
  };

  externalConfig = {
    output = "__EXTERNAL_OUTPUT__";
    layer = "top";
    position = "top";
    height = 60;
    spacing = 4;
    tray = { spacing = 10; icon-size = 18; };
  };

  internalWidgets = commonWidgetsBase // { "hyprland/workspaces" = workspaceInternal; };
  externalWidgets = commonWidgetsBase // { "hyprland/workspaces" = workspaceExternal; };

in
[
  (externalConfig // commonModules // externalWidgets)

  ({
    output = "__INTERNAL_OUTPUT__";
    layer = "top";
    position = "top";
    height = 80;
    spacing = 6;
    tray = { spacing = 12; icon-size = 20; };
  } // commonModules // internalWidgets)
]
