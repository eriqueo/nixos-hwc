# nixos-hwc/modules/home/theme/palettes/deep-nord.nix
#
# Global Theme Tokens: Deep Nord Palette
# Charter v4 compliant - Pure data tokens for theming adapters
#
# DEPENDENCIES (Upstream):
#   - None (source of truth)
#
# USED BY (Downstream):
#   - modules/home/theme/adapters/*.nix
#
# USAGE:
#   let palette = import ./palettes/deep-nord.nix {};
#   in palette.accent  # "#7daea3"
#

{ }:
{
  name = "deep-nord";
  
  # Background colors
  bg = "#2e3440";        # Main background
  bgAlt = "#3b4252";     # Alternative background
  bgDark = "#0B1115";    # Darker variant
  
  # Foreground colors  
  fg = "#ECEFF4";        # Main text
  muted = "#4C566A";     # Muted text
  
  # Accent colors
  accent = "#7daea3";    # Primary accent (teal)
  accentAlt = "#89b482"; # Secondary accent (green)
  
  # Status colors
  good = "#A3BE8C";      # Success/good state
  warn = "#EBCB8B";      # Warning state
  crit = "#BF616A";      # Critical/error state
  
  # Gruvbox Material colors (for Hyprland borders)
  gruvboxTeal = "7daea3ff";
  gruvboxGreen = "89b482ff";  
  gruvboxMuted = "45403daa";
}