{ lib, pkgs, osConfig ? {}, ... }:

let
  commonModules = {
    modules-left = [ "custom/ws-enter" "hyprland/workspaces" "hyprland/submap" ];
    modules-center = [ "clock" "custom/weather" ];
    modules-right = [
      "custom/sep-pre"
      "custom/gpu" "custom/ollama" "idle_inhibitor" "custom/lid-sleep"
      "custom/sep-1"
      "pulseaudio" "bluetooth" "custom/network"
      "custom/sep-2"
      "temperature" "custom/disk-space" "custom/battery"
      "custom/sep-3"
      "custom/proton-auth" "tray" "custom/notification" "custom/power"
    ];
  };

  workspaceInternal = {
    disable-scroll = true;
    all-outputs = false;
    warp-on-scroll = false;
    format = "{name}";
    "swap-icon-label" = false;
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
    "swap-icon-label" = false;
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
    "hyprland/submap" = { format = "mode: {}"; max-length = 12; tooltip = false; };
    "hyprland/window" = {
      format = "{title}";
      max-length = 40;
      separate-outputs = true;
      rewrite = {
        "(.*) — Mozilla Firefox" = "$1";
        "(.*) - Google Chrome" = "$1";
        "(.*) - Chromium" = "$1";
        "(.*) - Visual Studio Code" = "$1";
        "(.*) - nvim" = "$1";
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
    idle_inhibitor = { format = "{icon}"; format-icons = { activated = "Awake"; deactivated = "Idle"; }; };
    pulseaudio = { format = "{icon} {volume}%"; format-muted = "󰝟 Muted"; format-icons = { default = ["󰕿" "󰖀" "󰖁"]; }; on-click = "pavucontrol"; };
    "custom/network" = { format = "{}"; exec = "waybar-network-status"; return-type = "json"; interval = 5; on-click = "waybar-network-settings"; };
    bluetooth = { format = "󰂯"; format-connected = "󰂱 {num_connections}"; format-disabled = "󰂲"; tooltip-format-connected = "{device_enumerate}"; on-click = "blueman-manager"; };
    temperature = {
      hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
      input-filename = "temp1_input";
      critical-threshold = 80;
      format = "{temperatureC}°C";
      format-critical = "{temperatureC}°C!";
    };
    "custom/power-profile" = { format = "{}"; exec = "waybar-power-profile"; return-type = "json"; interval = 10; on-click = "waybar-power-profile-toggle"; };
    "custom/disk-space" = { format = "{}"; exec = "waybar-disk-space"; return-type = "json"; interval = 30; on-click = "baobab"; };
    "custom/battery" = { format = "{}"; exec = "waybar-battery-health"; return-type = "json"; interval = 5; on-click = "waybar-power-settings"; };
    "custom/proton-auth" = { format = "Auth"; tooltip = "Proton Authenticator (SUPER+A)"; on-click = "proton-authenticator-toggle"; };
    "custom/notification" = { format = "󰂚"; tooltip = "Notifications"; on-click = "swaync-client -t -sw"; };
    "custom/power" = { format = "Pwr"; tooltip = "Shutdown"; on-click = "wlogout"; };
    "custom/lid-sleep" = { format = "{}"; exec = "waybar-lid-status"; return-type = "json"; interval = 5; on-click = "waybar-lid-toggle"; };

    # === NEW: Weather for Bozeman ===
    "custom/weather" = {
      format = "{}";
      exec = "waybar-weather";
      return-type = "json";
      interval = 1800;
      on-click = "kitty --single-instance --hold -e bash -c 'curl -s wttr.in/Bozeman?u && echo -e \"\\n\\n────────────────────────────\\nPress any key to close...\" && read -n 1 -s -r'";
    };
    

    # Powerline separators — right-pointing arrows between right-side module groups
    # fg = left group bg, bg = right group bg (creates the arrow effect)
    "custom/ws-enter" = { format = ""; tooltip = false; };  # entry: dark → teal workspace
    "custom/sep-pre"  = { format = ""; tooltip = false; };  # bar → toggle
    "custom/sep-1"   = { format = ""; tooltip = false; };  # toggle → conn
    "custom/sep-2"   = { format = ""; tooltip = false; };  # conn → health
    "custom/sep-3"   = { format = ""; tooltip = false; };  # health → actions
  };

  externalConfig = {
    output = "__EXTERNAL_OUTPUT__";
    layer = "top";
    position = "top";
    height = 32;
    spacing = 0;
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
    height = 36;
    spacing = 0;
    tray = { spacing = 12; icon-size = 20; };
  } // commonModules // internalWidgets)
]
