# nixos-hwc/modules/home/hyprland.nix
#
# Home UI: Hyprland (HM consumer via NixOS orchestrator)
# NixOS options gate inclusion; Home-Manager config lives under home-manager.users.<user>.
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports HM and sets home.stateVersion)
#   - home-manager.nixosModules.home-manager (enabled at flake/machine)
#
# USED BY (Downstream):
#   - machines/*/config.nix  (e.g., hwc.desktop.hyprland.enable = true)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (or any profile that wants Hyprland)
#
# USAGE:
#   hwc.desktop.hyprland.enable = true;
#   hwc.desktop.hyprland.keybinds.modifier = "SUPER";
#   hwc.desktop.hyprland.keybinds.extra = [ "$mod, R, exec, wofi --show drun" ];
#   # Optional:
#   #   hwc.desktop.hyprland.monitor = "eDP-1,1920x1200@60,0x0,1";
#   #   hwc.desktop.hyprland.settings = { ... };
#   #   hwc.desktop.hyprland.extraConfig = '' ... '';

{ config, lib, pkgs, ... }:

let
  t   = lib.types;
  cfg = config.hwc.desktop.hyprland;
in
{
  #============================================================================
  # OPTIONS (NixOS layer) - feature gate and simple knobs
  #============================================================================
  options.hwc.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";

    monitor = lib.mkOption {
      type = t.nullOr t.str;
      default = null;
      description = "Hyprland monitor directive (e.g. \"eDP-1,1920x1200@60,0x0,1\").";
    };

    settings = lib.mkOption {
      type = t.attrsOf t.anything;
      default = {};
      description = "Additional Hyprland settings (merged with defaults).";
    };

    extraConfig = lib.mkOption {
      type = t.nullOr t.lines;
      default = null;
      description = "Extra Hyprland config as literal text.";
    };

    # Nvidia-specific switch used by profiles/workstation.nix
    nvidia = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Nvidia-specific Hyprland env/workarounds for Wayland sessions.";
    };


    # ---- NEW: keybinds shim to match profiles/workstation.nix ----------------
    keybinds = {
      modifier = lib.mkOption {
        type = t.str;
        default = "SUPER";
        description = "Modifier symbol assigned to $mod in Hyprland (e.g., SUPER, ALT).";
      };

      extra = lib.mkOption {
        type = t.listOf t.str;
        default = [];
        description = "Additional Hyprland 'bind' entries (strings) to append.";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION (NixOS -> HM bridge) - put HM config under users.<name>
  #============================================================================
  config = lib.mkIf cfg.enable {

    home-manager.useGlobalPkgs = lib.mkDefault true;

    home-manager.users.eric = { ... }: {
      home.packages = with pkgs; [
        hyprpaper hypridle hyprlock wofi kitty grim slurp wl-clipboard
        brightnessctl playerctl pamixer swaynotificationcenter
      ];

      wayland.windowManager.hyprland = {
        enable  = true;
        package = pkgs.hyprland;

       settings =
              let
                baseBinds = [
                  "$mod, RETURN, exec, kitty"
                  "$mod, Q, killactive"
                  "$mod, F, togglefloating"
                  "$mod, SPACE, exec, wofi --show drun"
                  "$mod SHIFT, E, exit"
                  "$mod, H, movefocus, l"
                  "$mod, J, movefocus, d"
                  "$mod, K, movefocus, u"
                  "$mod, L, movefocus, r"
                  "$mod CTRL, H, resizeactive, -20 0"
                  "$mod CTRL, L, resizeactive, 20 0"
                ];

                base = {
                  monitor = lib.mkIf (cfg.monitor != null) [ cfg.monitor ];
                  exec-once = [ "swaync" "hyprpaper" "waybar" ];

                  "$mod" = cfg.keybinds.modifier;
                  bind   = baseBinds ++ cfg.keybinds.extra;

                  animations.enabled = true;
                  xwayland.force_zero_scaling = true;

                  general = {
                    gaps_in  = 6;
                    gaps_out = 12;
                    border_size = 2;
                    allow_tearing = false;
                  };

                  input = {
                    kb_layout = "us";
                    follow_mouse = 1;
                    touchpad = {
                      natural_scroll = true;
                      tap            = true;
                    };
                  };

                  decoration = {
                    rounding = 8;
                    blur = { enabled = true; size = 6; passes = 2; };
                  };
                };

                # Extra env tweaks that help Nvidia on Wayland/Hyprland
                nvidiaExtra = lib.optionalAttrs cfg.nvidia {
                  # Hyprland's HM module expects a list of "VAR,VALUE" entries
                  env = [
                    "LIBVA_DRIVER_NAME,nvidia"
                    "GBM_BACKENDS_PATH,/run/opengl-driver/lib/gbm"
                    "WLR_NO_HARDWARE_CURSORS,1"
                  ];
                };
              in
                base // nvidiaExtra // cfg.settings;


        extraConfig = lib.mkIf (cfg.extraConfig != null) cfg.extraConfig;
      };

      xdg = {
        enable = true;
        portal.enable = true;
        portal.extraPortals = [
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-hyprland
        ];
      };
    };
  };
}
