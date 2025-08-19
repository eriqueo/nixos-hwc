{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.desktop.waybar;
     in {
       options.hwc.desktop.waybar = {
         enable = lib.mkEnableOption "Waybar status bar";

         position = lib.mkOption {
           type = lib.types.enum [ "top" "bottom" ];
           default = "top";
           description = "Waybar position";
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
         };
       };

       config = lib.mkIf cfg.enable {
         programs.waybar.enable = true;

         environment.etc."waybar/config".text = builtins.toJSON {
           layer = "top";
           position = cfg.position;
           height = 30;
           spacing = 4;

           modules-left = [ "hyprland/workspaces" "hyprland/mode"
     ];
           modules-center = [ "hyprland/window" ];
           modules-right = [ "idle_inhibitor" "network" "cpu"
     "memory" "temperature" "battery" "clock" "tray" ];

           "hyprland/workspaces" = lib.mkIf
     cfg.modules.showWorkspaces {
             disable-scroll = true;
             all-outputs = true;
             format = "{icon}";
             format-icons = {
               "1" = "";
               "2" = "";
               "3" = "";
               "4" = "";
               "5" = "";
               urgent = "";
               focused = "";
               default = "";
             };
           };

           keyboard-state = {
             numlock = true;
             capslock = true;
             format = "{name} {icon}";
             format-icons = {
               locked = "";
               unlocked = "";
             };
           };

           clock = {
             tooltip-format = "<big>{:%Y
     %B}</big>\n<tt><small>{calendar}</small></tt>";
             format-alt = "{:%Y-%m-%d}";
           };

           cpu = {
             format = "{usage}% ";
             tooltip = false;
           };

           memory = {
             format = "{}% ";
           };

           temperature = {
             critical-threshold = 80;
             format = "{temperatureC}°C {icon}";
             format-icons = [ "" "" "" ];
           };

           battery = lib.mkIf cfg.modules.showBattery {
             states = {
               warning = 30;
               critical = 15;
             };
             format = "{capacity}% {icon}";
             format-charging = "{capacity}% ";
             format-plugged = "{capacity}% ";
             format-alt = "{time} {icon}";
             format-icons = [ "" "" "" "" "" ];
           };

           network = lib.mkIf cfg.modules.showNetwork {
             format-wifi = "{essid} ({signalStrength}%) ";
             format-ethernet = "{ipaddr}/{cidr} ";
             tooltip-format = "{ifname} via {gwaddr} ";
             format-linked = "{ifname} (No IP) ";
             format-disconnected = "Disconnected ⚠";
             format-alt = "{ifname}: {ipaddr}/{cidr}";
           };
         };

         environment.etc."waybar/style.css".text = ''
           * {
               border: none;
               border-radius: 0;
               font-family: "JetBrains Mono Nerd Font";
               font-size: 13px;
               min-height: 0;
           }

           window#waybar {
               background-color: rgba(43, 48, 59, 0.5);
               border-bottom: 3px solid rgba(100, 114, 125, 0.5);
               color: #ffffff;
               transition-property: background-color;
               transition-duration: .5s;
           }

           #workspaces button {
               padding: 0 5px;
               background-color: transparent;
               color: #ffffff;
               border-bottom: 3px solid transparent;
           }

           #workspaces button:hover {
               background: rgba(0, 0, 0, 0.2);
               box-shadow: inset 0 -3px #ffffff;
           }

           #workspaces button.focused {
               background-color: #64727D;
               border-bottom: 3px solid #ffffff;
           }

           #clock,
           #battery,
           #cpu,
           #memory,
           #temperature,
           #network {
               padding: 0 10px;
               color: #ffffff;
           }

           #battery.charging, #battery.plugged {
               color: #ffffff;
               background-color: #26A65B;
           }

           #battery.critical:not(.charging) {
               background-color: #f53c3c;
               color: #ffffff;
               animation-name: blink;
               animation-duration: 0.5s;
               animation-timing-function: linear;
               animation-iteration-count: infinite;
               animation-direction: alternate;
           }
         '';
       };
     }
