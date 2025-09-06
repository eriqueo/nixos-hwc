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

    settings = s;
  };
}

