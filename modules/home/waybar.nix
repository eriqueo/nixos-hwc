# nixos-hwc/modules/home/waybar.nix
#
# Home UI: Waybar configuration (HM consumer)
# Pure config; helper scripts are provided by waybar-scripts.nix.
#
# DEPENDENCIES:
#   - modules/home/waybar-scripts.nix (installs network-status, battery-health, gpu-menu, …)
#   - modules/system/gpu.nix (provides gpu-toggle/gpu-status/etc. at system level)
#
# USED BY:
#   - profiles/workstation.nix (imports + sets hwc.desktop.waybar options)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.desktop.waybar;
in
{
  options.hwc.desktop.waybar = {
    enable   = lib.mkEnableOption "Waybar status bar";
    position = lib.mkOption { type = lib.types.enum [ "top" "bottom" ]; default = "top"; };
    height   = lib.mkOption { type = lib.types.int; default = 60; };
    modules  = {
      showWorkspaces   = lib.mkOption { type = lib.types.bool; default = true;  };
      showNetwork      = lib.mkOption { type = lib.types.bool; default = true;  };
      showBattery      = lib.mkOption { type = lib.types.bool; default = true;  };
      showGpuStatus    = lib.mkOption { type = lib.types.bool; default = true;  };
      showSystemMonitor= lib.mkOption { type = lib.types.bool; default = true;  };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.waybar = {
      enable = true;

      settings = [{
        layer = "top";
        position = cfg.position;
        height = cfg.height;
        spacing = 4;

        modules-left   = [ "hyprland/workspaces" "hyprland/submap" ];
        modules-center = [ "hyprland/window" "clock" ];
        modules-right  = [
          (lib.mkIf cfg.modules.showGpuStatus    "custom/gpu")
          "custom/disk"
          "idle_inhibitor"
          "mpd"
          "pulseaudio"
          (lib.mkIf cfg.modules.showNetwork      "custom/network")
          (lib.mkIf cfg.modules.showSystemMonitor "memory")
          (lib.mkIf cfg.modules.showSystemMonitor "cpu")
          "temperature"
          (lib.mkIf cfg.modules.showBattery      "custom/battery")
          "tray"
          "custom/notification"
          "custom/power"
        ] |> builtins.filter (x: x != null);

        "hyprland/workspaces" = lib.mkIf cfg.modules.showWorkspaces {
          disable-scroll = true;
          all-outputs = false;
          warp-on-scroll = false;
          format = "{icon}";
          format-icons = { "1"="󰈹"; "2"="󰭹"; "3"="󰏘"; "4"="󰎞"; "5"="󰕧"; "6"="󰊢"; "7"="󰋩"; "8"="󰚌"; active=""; default=""; urgent=""; };
          persistent-workspaces = { "1"=[]; "2"=[]; "3"=[]; "4"=[]; "5"=[]; "6"=[]; "7"=[]; "8"=[]; };
          on-click = "activate";
        };

        "hyprland/submap" = { format = "✨ {}"; max-length = 8; tooltip = false; };
        "hyprland/window" = { format = "{title}"; max-length = 50; separate-outputs = true; };

        clock = { interval = 1; format = "{:%H:%M:%S}"; format-alt = "{:%Y-%m-%d %H:%M:%S}"; tooltip-format = "<tt><small>{calendar}</small></tt>"; };

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
          interval = 2;
          state-icons = { paused = ""; playing = ""; };
          on-click = "mpc toggle";
          on-click-right = "mpc next";
          on-click-middle = "mpc prev";
          on-scroll-up = "mpc volume +2";
          on-scroll-down = "mpc volume -2";
        };

        idle_inhibitor = { format = "{icon}"; format-icons = { activated = "󰛨"; deactivated = "󰛧"; }; tooltip = true; };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons.default = [ "󰕿" "󰖀" "󰖁" ];
          on-click = "pavucontrol";
          on-scroll-up = "pulsemixer --change-volume +5";
          on-scroll-down = "pulsemixer --change-volume -5";
          tooltip = true;
        };

        "custom/network" = { format = "{}"; exec = "network-status"; return-type = "json"; interval = 5; on-click = "network-settings"; };

        memory = { format = "󰍛 {percentage}%"; interval = 5; tooltip = true; on-click = "system-monitor"; };
        cpu    = { format = "󰻠 {usage}%";    interval = 5; tooltip = true; on-click = "system-monitor"; };

        temperature = { thermal-zone = 0; critical-threshold = 80; format = "󰔏 {temperature}°C"; interval = 5; tooltip = true; on-click = "sensor-viewer"; };

        "custom/battery" = { format = "{}"; exec = "battery-health"; return-type = "json"; interval = 5; tooltip = true; on-click = "power-settings"; };

        tray = { spacing = 10; icon-size = 18; };

        "custom/notification" = {
          format = "{icon}";
          exec = "swaynotificationcenter-client -c count";
          interval = 1;
          tooltip = true;
          on-click = "swaynotificationcenter-client -t";
          format-icons = { "default" = "󰂚"; "0" = "󰂛"; };
        };

        "custom/power" = { format = "󰐥"; tooltip = "Shutdown"; on-click = "wlogout"; };
      }];

      # keep CSS literal to avoid accidental Nix interpolation
      style = ''
        @define-color background #282828;
        @define-color foreground #d4be98;
        @define-color accent     #7daea3;
        @define-color warning    #d8a657;
        @define-color error      #ea6962;
        @define-color success    #a9b665;
        @define-color info       #7daea3;

        * { border-radius: 0; font-family: "Fira Sans", sans-serif; font-size: 14px; }
        window#waybar { background-color: @background; color: @foreground; }
        #workspaces button { padding: 0 5px; background: transparent; color: @foreground; border-bottom: 2px solid transparent; }
        #workspaces button.active { color: @accent; border-bottom: 2px solid @accent; }
        #workspaces button.urgent { color: @error;  border-bottom: 2px solid @error; }
        #clock,#battery,#cpu,#memory,#temperature,#network,#pulseaudio,#custom-gpu,
        #idle_inhibitor,#tray,#custom-notification,#custom-power {
          padding: 0 10px; margin: 0 5px; color: @foreground;
        }
        .intel { color: #7daea3; } .nvidia { color: #a9b665; } .performance { color: #ea6962; }
        #battery.charging { color: @success; }
        #battery.critical:not(.charging) { color: @error; animation: blink 0.5s linear infinite alternate; }
      '';
    };

    # user packages Waybar might call directly (mix with scripts module if you like)
    home.packages = with pkgs; [
      pavucontrol swaynotificationcenter wlogout
      xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
      mpc-cli
    ];
  };
}
