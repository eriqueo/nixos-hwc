# nixos-h../domains/home/theme/palettes/deep-nord.nix
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

  # RENAMED: avoid collision with pointer-theme object below
  cursorColor = "7daea3";  # text-caret / selection handles, not the pointer theme
  caret       = "7daea3";  # alias for readability

  link        = "88c0d0";
  border      = "434C5E";
  borderDim   = "3b4252";

  # --- ANSI 16 (term adapters like Kitty/Alacritty/WezTerm) ---
  ansi = {
    black   = "45403d";
    red     = "BF616A";
    green   = "A3BE8C";
    yellow  = "EBCB8B";
    blue    = "7daea3";
    magenta = "d3869b";
    cyan    = "89b482";
    white   = "ECEFF4";

    brightBlack   = "4C566A";
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
  hypr = {
    teal   = "7daea3";
    green  = "89b482";
    muted  = "45403d";
  };

  # Legacy keys kept for back-compat (can be removed after adapters migrate)
  gruvboxTeal  = "7daea3ff";
  gruvboxGreen = "89b482ff";
  gruvboxMuted = "45403daa";

  # --- Pointer theme config (palette-driven)
  # GTK/Qt use XCursor; Hyprland uses Hyprcursor. Keep them in sync here.
  cursor = {
    size = 24;

    # GTK/Qt side (XCursor)
    xcursor = {
      name    = "Nordzy-cursors";
      package = "nordzy-cursor-theme";  # pkgs.<this>
    };

    # Hyprland side (Hyprcursor)
    hyprcursor = {
      name         = "Nordzy-hyprcursors";
      # path in your repo containing the hyprcursor assets (manifest.hl + hyprcursors/)
      # The Hyprland-session adapter will link this into ~/.local/share/icons
      assetPathRel = "modules/home/theme/assets/cursors/Nordzy-hyprcursors";
    };
  };
}
