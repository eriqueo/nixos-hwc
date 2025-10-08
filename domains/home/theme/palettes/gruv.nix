# modules/home/theme/palettes/gruv.nix
# Gruvbox Material Dark - Expanded tokens for rich UI theming
{ }:
{
  name = "gruv";

  # --- Background Hierarchy (4 shades for rich UI depth) ---
  bg0      = "1d2021";  # Deepest: modals, masks, deepest overlays
  bg1      = "282828";  # Main: primary background
  bg2      = "3c3836";  # Elevated: sidebars, inactive tabs, raised surfaces
  bg3      = "504945";  # Highest: active elements, buttons, borders

  # Legacy aliases (keep for compatibility during transition)
  bg       = "282828";  # → bg1
  bgAlt    = "3c3836";  # → bg2
  bgDark   = "1d2021";  # → bg0
  surface0 = "32302f";  # intermediate shade
  surface1 = "3c3836";  # intermediate shade
  surface2 = "504945";  # intermediate shade

  # --- Foreground Hierarchy (4 levels for text prominence) ---
  fg0      = "ebdbb2";  # Brightest: headings, emphasis, key info
  fg1      = "d4be98";  # Normal: body text, primary content
  fg2      = "bdae93";  # Dimmed: secondary text, labels
  fg3      = "665c54";  # Muted: disabled, comments, dividers

  # Legacy aliases
  fg       = "d4be98";  # → fg1
  fgDim    = "bdae93";  # → fg2
  muted    = "665c54";  # → fg3

  # --- Primary Accents (main interaction colors) ---
  accent     = "7daea3"; # Teal: primary accent (tabs, modes, links)
  accentAlt  = "d3869b"; # Magenta: secondary accent
  accent2    = "89b482"; # Green: tertiary

  # --- Semantic Status Colors (base + variants) ---
  success       = "a9b665"; # Green: success states
  successBright = "b8bb26"; # Bright green: emphasis
  successDim    = "89b482"; # Teal green: subtle

  warning       = "d8a657"; # Yellow/orange: warnings
  warningBright = "fabd2f"; # Bright yellow: urgent

  error         = "ea6962"; # Red: errors
  errorBright   = "fb4934"; # Bright red: critical
  errorDim      = "cc241d"; # Dark red: broken/invalid

  info          = "7daea3"; # Teal: info/help

  # Legacy aliases
  good  = "a9b665";  # → success
  warn  = "d8a657";  # → warning
  crit  = "ea6962";  # → error

  # --- UI Element Colors (specific roles) ---
  # Selection & Marking
  selection   = "7daea3"; # Primary selection color
  selectionFg = "282828"; # Text on selection
  selectionBg = "7daea3"; # Selection background
  marked      = "d3869b"; # Marked items (magenta)
  markedAlt   = "89b482"; # Alt marked color (green)

  # Interactive Elements
  cursorColor = "d4be98"; # Text cursor
  caret       = "d4be98"; # Caret/insertion point
  link        = "7daea3"; # Hyperlinks
  linkHover   = "89b482"; # Hovered links

  # Borders & Separators
  border      = "504945"; # Main borders
  borderDim   = "3c3836"; # Subtle borders
  borderBright= "665c54"; # Emphasized borders
  separator   = "665c54"; # UI separators

  # Progress & Loading
  progress    = "7daea3"; # Progress bar fill
  progressBg  = "3c3836"; # Progress bar background

  # --- File Type Colors (for file managers) ---
  fileImage    = "d8a657"; # Yellow: images
  fileMedia    = "d3869b"; # Magenta: audio/video
  fileArchive  = "ea6962"; # Red: archives/compressed
  fileDocument = "89b482"; # Green: documents/PDFs
  fileCode     = "7daea3"; # Teal: source code
  fileExec     = "a9b665"; # Green: executables
  fileOrphan   = "cc241d"; # Dark red: broken links
  fileDir      = "7daea3"; # Teal: directories

  # --- ANSI 16 (term adapters like Kitty/Alacritty/WezTerm) ---
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
    brightRed     = "fb4934";
    brightGreen   = "b8bb26";
    brightYellow  = "fabd2f";
    brightBlue    = "83a598";
    brightMagenta = "d3869b";
    brightCyan    = "8ec07c";
    brightWhite   = "ebdbb2";
  };

  # --- Hyprland helpers (pre-alpha hex chunks when you need rgba) ---
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft   = "aa";
    faint  = "66";
  };

  # For convenience with Hyprland's "rgba(RRGGBBAA)" border strings.
  hypr = {
    teal   = "7daea3";
    green  = "89b482";
    muted  = "45403d";
  };

  # --- Pointer theme config (palette-driven) ---
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