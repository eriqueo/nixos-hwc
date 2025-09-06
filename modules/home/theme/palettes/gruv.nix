{ }:
{
  name = "deep-nord";

  # --- Neutrals / backgrounds ---
  bg       = "#282828";  # main background
  bgAlt    = "#3b4252";  # alt background (headers/sidebars)
  bgDark   = "#0B1115";  # very dark (overlays, popups)
  surface0 = "#2f3541";  # panels / cards
  surface1 = "#343b49";  # raised panels
  surface2 = "#394152";  # most raised

  # --- Foregrounds ---
  fg       = "#d4be98";  # primary text
  fgDim    = "#d8dee9";  # secondary text
  muted    = "#4C566A";  # muted/disabled

  # --- Accents / status ---
  accent     = "#7daea3"; # teal (primary)
  accentAlt  = "#89b482"; # green (secondary)
  accent2    = "#88c0d0"; # nord cyan (optional tertiary)

  good  = "#A3BE8C";
  warn  = "#EBCB8B";
  crit  = "#BF616A";
  info  = "#81A1C1";

  # --- UI roles (common adapters can read these) ---
  selectionFg = "#282828";
  selectionBg = "#7daea3";
  cursor      = "#d4be98";
  cursor_text = "#282828";
  link        = "#88c0d0";
  border      = "#434C5E";
  borderDim   = "#3b4252";

  # --- ANSI 16 (term adapters like Kitty/Alacritty/WezTerm) ---
  # Normal
  ansi = {
    black   = "#32302F";  # gruvbox-ish dark
    red     = "#ea6962";  # crit
    green   = "#a9b665";  # good
    yellow  = "#d8a657";  # warn
    blue    = "#7daea3";  # accent (teal)
    magenta = "#d3869b";  # gruvbox magenta
    cyan    = "#89b482";  # accentAlt (greenish)
    white   = "#d4be98";  # fg

    # Bright
    brightBlack   = "#45403d"; # muted
    brightRed     = "#ea6962";
    brightGreen   = "#a9b665";
    brightYellow  = "#d8a657";
    brightBlue    = "#7daea3";
    brightMagenta = "#d3869b";
    brightCyan    = "#89b482";
    brightWhite   = "#d4be98";
  };
    # Nord semantic colors for UI elements
    nord0  = "#1f2329";  # darkest (our custom background)
    nord1  = "#3b4252";  # dark
    nord2  = "#434c5e";  # medium dark
    nord3  = "#4c566a";  # medium
    nord4  = "#d8dee9";  # medium light
    nord5  = "#e5e9f0";  # light
    nord6  = "#f2f0e8";  # lightest (our custom foreground)
    nord7  = "#8fbcbb";  # frost cyan
    nord8  = "#88c0d0";  # frost blue
    nord9  = "#81a1c1";  # frost light blue
    nord10 = "#5e81ac";  # frost dark blue
    nord11 = "#bf616a";  # aurora red
    nord12 = "#d08770";  # aurora orange
    nord13 = "#ebcb8b";  # aurora yellow
    nord14 = "#a3be8c";  # aurora green
    nord15 = "#b48ead";  # aurora purple
    
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

  # Transparency values
  opacity_terminal = "0.95";
  opacity_inactive = "0.90";
  
  # CSS/Web colors (with # prefix for web use) - Gruvbox Material inspired
  css = {
    background = "#282828";
    foreground = "#d4be98";
    accent = "#7daea3";      # soft teal
    warning = "#d8a657";     # muted yellow
    error = "#ea6962";       # muted red
    success = "#a9b665";     # muted green
    info = "#7daea3";        # soft blue
}
