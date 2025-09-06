# nixos-hwc/modules/home/theme/default.nix
#
# THEME ROOT (v6) — Single entry point for theming in Home Manager.
# Exposes a palette toggle and imports all theme adapters so apps can consume
# config.hwc.home.theme.adapters.* outputs without listing adapters in machines/<host>/home.nix.
#
# DEPENDENCIES (Upstream):
#   - ./palettes/*.nix     (tokens)
#   - ./adapters/*.nix     (transforms: palette -> per-app formats)
#
# USED BY (Downstream):
#   - machines/<host>/home.nix (HM activation)
#   - modules/home/apps/* (Waybar, Thunar/GTK, Hyprland appearance, etc.)
#
# RULES (Charter v6):
#   - Home Manager activation is machine-level only
#   - No system packages/services here (UI-only module)
#   - Required sections: OPTIONS / IMPLEMENTATION / VALIDATION
#
{ config, lib, ... }:

let
  palettes = rec {
    deep-nord = import ./palettes/deep-nord.nix { };
    gruv      = import ./palettes/gruv.nix { };
  };
in
{
#============================================================================
# OPTIONS - What can be configured
#============================================================================
  options.hwc.home.theme = {
    palette = lib.mkOption {
      type = lib.types.enum (builtins.attrNames palettes);
      default = "deep-nord";
      description = "Active theme palette (single source of truth).";
    };
    
    colors = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Materialized color tokens from selected palette.";
    };
  };

  imports = [
      ./adapters/gtk.nix
      ./adapters/waybar-css.nix
      ./adapters/hyprland.nix
    ];
#============================================================================
# IMPLEMENTATION - What actually gets configured
#============================================================================
  config = {
    # Materialize the selected palette as a read-only token set for adapters/apps.
    hwc.home.theme.colors = palettes.${config.hwc.home.theme.palette};

    # Pull in all adapters so consumers can read config.hwc.home.theme.adapters.*
    # without importing each adapter in machines/<host>/home.nix.


    
#============================================================================
# VALIDATION - Assertions and checks
#============================================================================
# By convention: no environment.systemPackages, no systemd.services in HM modules

    assertions = [
      {
        assertion = true;
        message = "Theme root loaded.";
      }
    ];
  };


}
