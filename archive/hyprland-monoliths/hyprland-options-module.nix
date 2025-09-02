# nixos-hwc/modules/home/hyprland.nix
#
# Home UI: Hyprland Wayland Compositor (Pure Home-Manager Module)
# Charter v4 compliant - UI domain in Home-Manager, system bits in NixOS infrastructure
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#   - Infrastructure modules provide GPU drivers, portals, etc.
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports
#
# USAGE:
#   hwc.home.hyprland.enable = true;
#   hwc.home.hyprland.keybinds.modifier = "SUPER";
#   hwc.home.hyprland.keybinds.extra = [ "$mod, R, exec, wofi --show drun" ];
#   hwc.home.hyprland.startup = [ "waybar" "hyprpaper" "hypridle" ];
#   # Optional:
#   #   hwc.home.hyprland.monitor.primary = "eDP-1,1920x1200@60,0x0,1";
#   #   hwc.home.hyprland.settings = { ... };
#   #   hwc.home.hyprland.extraConfig = '' ... '';
#   #   hwc.home.hyprland.nvidia = true;

{ config, lib, pkgs, nixosConfig ? {}, ... }:

let
  t   = lib.types;
  cfg = config.hwc.home.hyprland;
in
{
  #============================================================================
  # OPTIONS (Home-Manager layer)
  #============================================================================
  options.hwc.home.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";

  monitor = lib.mkOption {
      type = lib.types.submodule {
        options = {
          primary = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Hyprland monitor string for the built-in/primary display (e.g. \"eDP-1,2560x1600@165,0x0,1.566667\").";
          };
          external = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Hyprland monitor string for the external display (e.g. \"DP-1,3840x2160@60,1638x0,2\").";
          };
        };
      };
      default = {};
      description = "Monitor layout strings passed to Hyprland.";
    };


    # Structured settings merged into HM
    settings = lib.mkOption {
      type = t.attrsOf t.anything;
      default = {};
      description = "Additional Hyprland settings (merged with defaults).";
    };

    # Raw text appended after structured settings
    extraConfig = lib.mkOption {
      type = t.nullOr t.lines;
      default = null;
      description = "Extra Hyprland config as literal text.";
    };

    # Profiles/workstation.nix shim: list of commands to run once
    startup = lib.mkOption {
      type = t.listOf t.str;
      default = [ "waybar" "hyprpaper" "hypridle" ];
      description = "Commands run via Hyprland exec-once (deduped with defaults).";
    };

    # Nvidia Wayland niceties
    nvidia = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Nvidia-specific Hyprland env tweaks.";
    };

    # Keybind facade expected by workstation.nix
    keybinds = {
      modifier = lib.mkOption {
        type = t.str;
        default = "SUPER";
        description = "Modifier symbol bound to $mod (e.g., SUPER, ALT).";
      };

      extra = lib.mkOption {
        type = t.listOf t.str;
        default = [];
        description = "Additional Hyprland 'bind' entries to append.";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION (Pure Home-Manager)
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Home-Manager packages for Hyprland ecosystem
    home.packages = with pkgs; [
      hyprpaper hypridle hyprlock wofi kitty grim slurp wl-clipboard
      brightnessctl playerctl pamixer swaynotificationcenter
    ];

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;

      settings =
        let
          # base binds
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

          # defaults we'd normally start (also provided as startup default)
          defaultExec = [ "swaync" "hyprpaper" "waybar" ];

          # nvidia env map (Hypr expects list of "VAR,VALUE")
          nvidiaExtra = lib.optionalAttrs cfg.nvidia {
            env = [
              "LIBVA_DRIVER_NAME,nvidia"
              "GBM_BACKENDS_PATH,/run/opengl-driver/lib/gbm"
              "WLR_NO_HARDWARE_CURSORS,1"
            ];
          };

          # Monitor configuration
          monitorList = lib.filter (x: x != null) [
            cfg.monitor.primary
            cfg.monitor.external
          ];

          base = {
            monitor = lib.mkIf (monitorList != []) monitorList;

            # merge: user startup + defaultExec + dedupe
            exec-once = lib.unique (cfg.startup ++ defaultExec);

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
        in
          base // nvidiaExtra // cfg.settings;

      extraConfig = lib.mkIf (cfg.extraConfig != null) cfg.extraConfig;
    };

    # XDG portals (Home-Manager manages user portals)
    xdg = {
      enable = true;
      portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-hyprland
        ];
        config.common.default = "*";  # Keep < 1.17 behavior
      };
    };
  };
}
