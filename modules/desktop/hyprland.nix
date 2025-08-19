{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.desktop.hyprland;
     in {
       options.hwc.desktop.hyprland = {
         enable = lib.mkEnableOption "Hyprland Wayland compositor";

         nvidia = lib.mkEnableOption "NVIDIA-specific
     optimizations";

         keybinds = {
           modifier = lib.mkOption {
             type = lib.types.str;
             default = "SUPER";
             description = "Main modifier key";
           };
         };

         monitor = {
           primary = lib.mkOption {
             type = lib.types.str;
             default = "eDP-1,2560x1600@165,0x0,1.566667";
             description = "Primary monitor configuration";
           };
           external = lib.mkOption {
             type = lib.types.str;
             default = "DP-1,3840x2160@60,1638x0,2";
             description = "External monitor configuration";
           };
         };

         startup = lib.mkOption {
           type = lib.types.listOf lib.types.str;
           default = [
             "waybar"
             "hyprpaper"
             "hypridle"
           ];
           description = "Applications to start with Hyprland";
         };
       };

       config = lib.mkIf cfg.enable {
         programs.hyprland = {
           enable = true;
           xwayland.enable = true;
         };

         environment.sessionVariables = lib.mkIf cfg.nvidia {
           # NVIDIA Wayland optimizations
           LIBVA_DRIVER_NAME = "nvidia";
           XDG_SESSION_TYPE = "wayland";
           GBM_BACKEND = "nvidia-drm";
           __GLX_VENDOR_LIBRARY_NAME = "nvidia";
           WLR_NO_HARDWARE_CURSORS = "1";
         };

         # Hyprland configuration file
         environment.etc."hypr/hyprland.conf".text = ''
           # Monitor configuration
           monitor = ${cfg.monitor.primary}
           monitor = ${cfg.monitor.external}

           # Input configuration
           input {
               kb_layout = us
               follow_mouse = 1
               touchpad {
                   natural_scroll = yes
               }
               sensitivity = 0
           }

           # General settings
           general {
               gaps_in = 5
               gaps_out = 10
               border_size = 2
               col.active_border = rgba(33ccffee) rgba(00ff99ee)
     45deg
               col.inactive_border = rgba(595959aa)
               layout = dwindle
           }

           # Decoration
           decoration {
               rounding = 10
               blur {
                   enabled = true
                   size = 3
                   passes = 1
               }
               drop_shadow = yes
               shadow_range = 4
               shadow_render_power = 3
               col.shadow = rgba(1a1a1aee)
           }

           # Animations
           animations {
               enabled = yes
               bezier = myBezier, 0.05, 0.9, 0.1, 1.05
               animation = windows, 1, 7, myBezier
               animation = windowsOut, 1, 7, default, popin 80%
               animation = border, 1, 10, default
               animation = borderangle, 1, 8, default
               animation = fade, 1, 7, default
               animation = workspaces, 1, 6, default
           }

           # Keybindings
           $mainMod = ${cfg.keybinds.modifier}

           bind = $mainMod, Q, exec, kitty
           bind = $mainMod, C, killactive,
           bind = $mainMod, M, exit,
           bind = $mainMod, E, exec, dolphin
           bind = $mainMod, V, togglefloating,
           bind = $mainMod, R, exec, rofi -show drun
           bind = $mainMod, P, pseudo,
           bind = $mainMod, J, togglesplit,

           # Move focus
           bind = $mainMod, left, movefocus, l
           bind = $mainMod, right, movefocus, r
           bind = $mainMod, up, movefocus, u
           bind = $mainMod, down, movefocus, d

           # Switch workspaces
           bind = $mainMod, 1, workspace, 1
           bind = $mainMod, 2, workspace, 2
           bind = $mainMod, 3, workspace, 3
           bind = $mainMod, 4, workspace, 4
           bind = $mainMod, 5, workspace, 5

           # Move active window to workspace
           bind = $mainMod SHIFT, 1, movetoworkspace, 1
           bind = $mainMod SHIFT, 2, movetoworkspace, 2
           bind = $mainMod SHIFT, 3, movetoworkspace, 3
           bind = $mainMod SHIFT, 4, movetoworkspace, 4
           bind = $mainMod SHIFT, 5, movetoworkspace, 5

           # Startup applications
           ${lib.concatMapStringsSep "\n" (app: "exec-once =
     ${app}") cfg.startup}
         '';

         # Required packages
         environment.systemPackages = with pkgs; [
           rofi-wayland
           waybar
           hyprpaper
           hypridle
           hyprlock
           kitty
           dolphin
           grim
           slurp
           wl-clipboard
         ];
       };
     }
