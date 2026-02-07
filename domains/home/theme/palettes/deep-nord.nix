# HWC Charter Module/domains/home/theme/palettes/deep-nord.nix
# Deep Nord — expanded tokens for apps & adapters (Charter v6)

{ osConfig ? {} }:
{
  name = "deep-nord";

  # --- Background Hierarchy (4 shades for rich UI depth) ---
  bg0      = "0B1115";  # Deepest: modals, masks, deepest overlays
  bg1      = "2e3440";  # Main: primary background
  bg2      = "3b4252";  # Elevated: sidebars, inactive tabs, raised surfaces
  bg3      = "434c5e";  # Highest: active elements, buttons, borders

  # Legacy aliases (keep for compatibility during transition)
  bg       = "2e3440";  # → bg1
  bgAlt    = "3b4252";  # → bg2
  bgDark   = "0B1115";  # → bg0
  surface0 = "2f3541";  # intermediate shade
  surface1 = "343b49";  # intermediate shade
  surface2 = "394152";  # intermediate shade

  # --- Foreground Hierarchy (4 levels for text prominence) ---
  fg0      = "ECEFF4";  # Brightest: headings, emphasis, key info
  fg1      = "E5E9F0";  # Normal: body text, primary content
  fg2      = "D8DEE9";  # Dimmed: secondary text, labels
  fg3      = "4C566A";  # Muted: disabled, comments, dividers

  # Legacy aliases
  fg       = "ECEFF4";  # → fg0
  fgDim    = "d8dee9";  # → fg2
  muted    = "4C566A";  # → fg3

  # --- Primary Accents (main interaction colors) ---
  accent     = "88c0d0"; # Cyan: primary accent (tabs, modes, links)
  accentAlt  = "81a1c1"; # Blue: secondary accent
  accent2    = "5e81ac"; # Dark blue: tertiary

  # --- Semantic Status Colors (base + variants) ---
  success       = "A3BE8C"; # Green: success states
  successBright = "a9b665"; # Bright green: emphasis
  successDim    = "8FBCBB"; # Teal green: subtle

  warning       = "EBCB8B"; # Yellow: warnings
  warningBright = "d8a657"; # Orange-yellow: urgent

  error         = "BF616A"; # Red: errors
  errorBright   = "ea6962"; # Bright red: critical
  errorDim      = "c34043"; # Dark red: broken/invalid

  info          = "81A1C1"; # Blue: info/help

  # Legacy aliases
  good  = "A3BE8C";  # → success
  warn  = "EBCB8B";  # → warning
  crit  = "BF616A";  # → error

  # --- UI Element Colors (specific roles) ---
  # Selection & Marking
  selection   = "88c0d0"; # Primary selection color
  selectionFg = "2e3440"; # Text on selection
  selectionBg = "88c0d0"; # Selection background
  marked      = "B48EAD"; # Marked items (violet)
  markedAlt   = "5e81ac"; # Alt marked color

  # Interactive Elements
  cursorColor = "88c0d0"; # Text cursor
  caret       = "88c0d0"; # Caret/insertion point
  link        = "81a1c1"; # Hyperlinks
  linkHover   = "5e81ac"; # Hovered links

  # Borders & Separators
  border      = "434C5E"; # Main borders
  borderDim   = "3b4252"; # Subtle borders
  borderBright= "4C566A"; # Emphasized borders
  separator   = "4C566A"; # UI separators

  # Progress & Loading
  progress    = "88c0d0"; # Progress bar fill
  progressBg  = "3b4252"; # Progress bar background

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

  # --- File Type Colors (for file managers) ---
  fileImage    = "EBCB8B"; # Yellow: images
  fileMedia    = "B48EAD"; # Violet: audio/video
  fileArchive  = "BF616A"; # Red: archives/compressed
  fileDocument = "8FBCBB"; # Teal: documents/PDFs
  fileCode     = "81A1C1"; # Blue: source code
  fileExec     = "A3BE8C"; # Green: executables
  fileOrphan   = "c34043"; # Dark red: broken links
  fileDir      = "88c0d0"; # Cyan: directories

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