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

{ lib, pkgs, ... }:
let
  palette = import ../../../theme/palettes/deep-nord.nix {};
in
  import ../../../theme/adapters/hyprland.nix { inherit palette; }
