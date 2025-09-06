# nixos-hwc/modules/home/hyprland/default.nix
#
# Home UI: Hyprland Wayland Compositor (Universal Config Domains)
# Charter v5 compliant - Single entrypoint composing universal behavior/hardware/session/appearance domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#   - modules/home/theme/palettes/deep-nord.nix (theme tokens)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#   Universal domains: behavior.nix, hardware.nix, session.nix, appearance.nix
#

# In modules/home/apps/hyprland/default.nix
{ config, lib, pkgs, ... }:

let
  # This module now reads its OWN enable flag from the options
  # defined in apps/default.nix
  cfg = config.hwc.home.apps.hyprland;
# The entire output of this file is wrapped in a lib.mkIf

    behavior = import ./parts/behavior.nix { inherit lib pkgs; };
    hardware = import ./parts/hardware.nix { inherit lib pkgs; };
    session = import ./parts/session.nix { inherit lib pkgs; };
    themeSettings = config.hwc.home.theme.adapters.hyprland.settings;
    appearance = import ./parts/appearance.nix { inherit lib pkgs; theme = themeSettings; };
    wallpaperPath = ./../../theme/nord-mountains.jpg;
  in
  lib.mkIf cfg.enable {
  
    home.packages = with pkgs; [
      wofi hyprshot hypridle hyprpaper hyprlock cliphist wl-clipboard
      brightnessctl networkmanager wirelesstools hyprsome
    ] ++ session.packages;

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    wayland.windowManager.hyprland = {
      enable = true;
      package = pkgs.hyprland;
      settings = lib.mkMerge [
        {
          monitor = hardware.monitor;
          workspace = hardware.workspace;
          input = hardware.input;
        }
        (behavior // { "$mod" = "SUPER"; })
        { exec-once = session.execOnce; }
        appearance
      ];
    };

    home.file.".config/hypr/hyprpaper.conf".text = ''
      preload = ${wallpaperPath}
      wallpaper = eDP-1,${wallpaperPath}
      wallpaper = DP-1,${wallpaperPath}
      splash = false
    '';
  }
  # --- End of existing code ---

}
