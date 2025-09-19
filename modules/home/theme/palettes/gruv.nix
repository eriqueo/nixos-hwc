# modules/home/theme/palettes/gruv.nix
{ }:
{
  name = "gruv";

  # --- Neutrals / backgrounds ---
  bg       = "282828";
  bgAlt    = "3b4252";
  bgDark   = "0B1115";
  surface0 = "2f3541";
  surface1 = "343b49";
  surface2 = "394152";

  # --- Foregrounds ---
  fg       = "d4be98";
  fgDim    = "d8dee9";
  muted    = "4C566A";

  # --- Accents / status ---
  accent     = "7daea3";  # soft teal
  accentAlt  = "d3869b";  # magenta-like
  accent2    = "88c0d0";  # frost cyan/blue

  good  = "a9b665";
  warn  = "d8a657";
  crit  = "ea6962";
  info  = "81A1C1";

  # --- UI roles ---
  selectionFg = "282828";
  selectionBg = "7daea3";
  cursorColor = "d4be98";  # caret alias
  caret       = "d4be98";
  link        = "88c0d0";
  border      = "434C5E";
  borderDim   = "3b4252";

  # --- ANSI 16 ---
  ansi = {
    black   = "32302F";
    red     = "ea6962";
    green   = "a9b665";
    yellow  = "d8a657";
    blue    = "7daea3";
    magenta = "d3869b";
    cyan    = "89b482";
    white   = "d4be98";

    brightBlack   = "45403d";
    brightRed     = "ea6962";
    brightGreen   = "a9b665";
    brightYellow  = "d8a657";
    brightBlue    = "7daea3";
    brightMagenta = "d3869b";
    brightCyan    = "89b482";
    brightWhite   = "d4be98";
  };

  # --- Alpha helpers ---
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft   = "aa";
    faint  = "66";
  };

  # --- Hypr helpers (for other adapters) ---
  hypr = {
    teal   = "7daea3";
    green  = "89b482";
    muted  = "45403d";
  };

  # Legacy for back-compat (optional)
  gruvboxTeal  = "7daea3ff";
  gruvboxGreen = "89b482ff";
  gruvboxMuted = "45403daa";

  # Cursor theme block used elsewhere (kept to match deep-nord)
  cursor = {
    size = 24;
    xcursor = {
      name    = "Nordzy-cursors";
      package = "nordzy-cursor-theme";
    };
    hyprcursor = {
      name         = "Nordzy-hyprcursors";
      assetPathRel = "modules/home/theme/assets/cursors/Nordzy-hyprcursors";
    };
  };
}
