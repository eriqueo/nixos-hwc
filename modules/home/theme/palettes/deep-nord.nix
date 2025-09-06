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
# nixos-hwc/modules/home/theme/palettes/deep-nord.nix
# Deep Nord — expanded tokens for apps & adapters (Charter v6)

{ }:
{
  name = "deep-nord";

  # --- Neutrals / backgrounds ---
  bg       = "2e3440";  # main background
  bgAlt    = "3b4252";  # alt background (headers/sidebars)
  bgDark   = "0B1115";  # very dark (overlays, popups)
  surface0 = "2f3541";  # panels / cards
  surface1 = "343b49";  # raised panels
  surface2 = "394152";  # most raised

  # --- Foregrounds ---
  fg       = "ECEFF4";  # primary text
  fgDim    = "d8dee9";  # secondary text
  muted    = "4C566A";  # muted/disabled

  # --- Accents / status ---
  accent     = "7daea3"; # teal (primary)
  accentAlt  = "89b482"; # green (secondary)
  accent2    = "88c0d0"; # nord cyan (optional tertiary)

  good  = "A3BE8C";
  warn  = "EBCB8B";
  crit  = "BF616A";
  info  = "81A1C1";

  # --- UI roles (common adapters can read these) ---
  selectionFg = "2e3440";
  selectionBg = "7daea3";
  cursor      = "7daea3";
  link        = "88c0d0";
  border      = "434C5E";
  borderDim   = "3b4252";

  # --- ANSI 16 (term adapters like Kitty/Alacritty/WezTerm) ---
  # Normal
  ansi = {
    black   = "45403d";  # gruvbox-ish dark
    red     = "BF616A";  # crit
    green   = "A3BE8C";  # good
    yellow  = "EBCB8B";  # warn
    blue    = "7daea3";  # accent (teal)
    magenta = "d3869b";  # gruvbox magenta
    cyan    = "89b482";  # accentAlt (greenish)
    white   = "ECEFF4";  # fg

    # Bright
    brightBlack   = "4C566A"; # muted
    brightRed     = "ea6962";
    brightGreen   = "a9b665";
    brightYellow  = "d8a657";
    brightBlue    = "7daea3";
    brightMagenta = "d3869b";
    brightCyan    = "89b482";
    brightWhite   = "d4be98";
  };

  # --- Hyprland helpers (pre-alpha hex chunks when you need rgba) ---
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft   = "aa";
    faint  = "66";
  };

  # For convenience with Hyprland’s "rgba(RRGGBBAA)" border strings.
  # Adapters can build: "rgba(${hypr.teal}${alpha.opaque})"
  hypr = {
    teal   = "7daea3";  # no leading '#'
    green  = "89b482";
    muted  = "45403d";
  };

  # Legacy keys kept for back-compat (can be removed after adapters migrate)
  gruvboxTeal  = "7daea3ff";
  gruvboxGreen = "89b482ff";
  gruvboxMuted = "45403daa";
}
