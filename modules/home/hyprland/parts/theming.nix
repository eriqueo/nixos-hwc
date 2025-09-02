# nixos-hwc/modules/home/hyprland/parts/theming.nix
#
# Hyprland Theming: Theme System Integration
# Charter v4 compliant - Pure data from theme adapter
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#   - modules/home/theme/adapters/hyprland.nix
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let theme = import ./parts/theming.nix { inherit lib pkgs; };
#   in theme  # Contains general, decoration, animations, dwindle, misc
#

{ lib, pkgs, ... }:
let
  palette = import ../../theme/palettes/deep-nord.nix {};
in
  import ../../theme/adapters/hyprland.nix { inherit palette; }