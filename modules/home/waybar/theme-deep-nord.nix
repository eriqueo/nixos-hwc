# nixos-hwc/modules/home/waybar/theme-deep-nord.nix
#
# Waybar Theme: Deep Nord (Global Theme System Integration)
# Charter v4 compliant - Uses global theme adapter instead of hardcoded CSS
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#   - modules/home/theme/adapters/waybar-css.nix
#
# USED BY (Downstream):
#   - modules/home/waybar/default.nix
#
# USAGE:
#   programs.waybar.style = import ./theme-deep-nord.nix {};
#

{ }:
let 
  palette = import ../theme/palettes/deep-nord.nix {};
in 
  import ../theme/adapters/waybar-css.nix { inherit palette; }