# nixos-hwc/modules/home/hyprland/parts/appearance.nix
#
# Hyprland Appearance: Theme System Integration
# Charter v5 compliant - Universal appearance domain for visual styling
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#   - modules/home/theme/adapters/hyprland.nix
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let appearance = import ./parts/appearance.nix { inherit lib pkgs; };
#   in appearance  # Contains general, decoration, animations, dwindle, misc
#

{ config, lib, ... }:

let
  s = config.hwc.home.theme.adapters.hyprland.settings;
in
{
  wayland.windowManager.hyprland = {
    enable = true;

    settings = lib.mkMerge [
      s
      {
        general = {
          gaps_in = 6;
          gaps_out = 12;
          border_size = 2;
          layout = "dwindle";
          resize_on_border = true;
          allow_tearing = false;
        };

        decoration = {
          rounding = 12;
          blur = {
            enabled = true;
            size = 6;
            passes = 3;
            new_optimizations = true;
            ignore_opacity = true;
          };
          shadow = {
            enabled = true;
            range = 8;
            render_power = 2;
            color = "rgba(0, 0, 0, 0.4)";
          };
          dim_inactive = false;
        };

        animations = {
          enabled = true;
          bezier = [
            "easeOutQuint,0.23,1,0.32,1"
            "easeInOutCubic,0.65,0.05,0.36,1"
            "linear,0,0,1,1"
          ];
          animation = [
            "windows,1,4,easeOutQuint,slide"
            "windowsOut,1,4,easeInOutCubic,slide"
            "border,1,10,default"
            "fade,1,4,default"
            "workspaces,1,4,easeOutQuint,slide"
          ];
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
          smart_split = false;
          smart_resizing = true;
        };

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          vrr = 1;
          enable_swallow = true;
          swallow_regex = "^(kitty)$";
          animate_manual_resizes = true;
          animate_mouse_windowdragging = true;
          focus_on_activate = true;
          new_window_takes_over_fullscreen = 2;
        };
      }
    ];
  };
}

