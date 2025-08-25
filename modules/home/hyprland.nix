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
#   # Optional (NixOS-side knobs):
#   #   hwc.desktop.hyprland.monitor = "eDP-1,1920x1200@60,0x0,1";
#   #   hwc.desktop.hyprland.settings = { "$mod" = "SUPER"; };
#   #   hwc.desktop.hyprland.extraConfig = '' # raw Hyprland lines ... '';

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

    # One common monitor line; if you need more, pass a list via settings.monitor instead.
    monitor = lib.mkOption {
      type = t.nullOr t.str;
      default = null;
      description = "Hyprland monitor directive (e.g. \"eDP-1,1920x1200@60,0x0,1\").";
    };

    # High-level map merged into HM settings (safe place for simple tuning)
    settings = lib.mkOption {
      type = t.attrsOf t.anything;
      default = {};
      description = "Additional Hyprland settings (merged with defaults).";
    };

    # Raw Hyprland text appended after structured settings
    extraConfig = lib.mkOption {
      type = t.nullOr t.lines;
      default = null;
      description = "Extra Hyprland config as literal text.";
    };
  };

  #============================================================================
  # IMPLEMENTATION (NixOS -> HM bridge) - put HM config under users.<name>
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Keep HM using the same pkgs as the system.
    home-manager.useGlobalPkgs = lib.mkDefault true;

    home-manager.users.eric = { ... }: {

      # Useful desktop tooling for Hyprland sessions
      home.packages = with pkgs; [
        hyprpaper
        hypridle
        hyprlock
        wofi
        kitty
        grim
        slurp
        wl-clipboard
        brightnessctl
        playerctl
        pamixer
        swaynotificationcenter
      ];

      # Main Hyprland configuration (correct HM key)
      wayland.windowManager.hyprland = {
        enable  = true;
        package = pkgs.hyprland;

        # Structured settings (safe defaults + your NixOS-side overrides)
        settings =
          let
            base = {
              # Monitor: accept a single line via NixOS knob if provided
              monitor = lib.mkIf (cfg.monitor != null) [ cfg.monitor ];

              exec-once = [
                "swaync"         # notifications
                "hyprpaper"      # wallpaper
                "waybar"         # status bar
              ];

              "$mod" = "SUPER";

              bind = [
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

              animations = {
                enabled = true;
              };

              xwayland = {
                force_zero_scaling = true;
              };

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
                blur = {
                  enabled = true;
                  size = 6;
                  passes = 2;
                };
              };
            };
          in
            base // cfg.settings;

        # Raw lines appended at the end if provided
        extraConfig = lib.mkIf (cfg.extraConfig != null) cfg.extraConfig;
      };

      # XDG portal wiring (can also be done system-wide; harmless to keep here)
      xdg = {
        enable = true;
        portal = {
          enable = true;
          extraPortals = [
            pkgs.xdg-desktop-portal-gtk
            pkgs.xdg-desktop-portal-hyprland
          ];
        };
      };
    };
  };
}
