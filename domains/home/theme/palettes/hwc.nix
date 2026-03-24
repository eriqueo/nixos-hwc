# domains/home/theme/palettes/hwc.nix
# Heartwood Craft — Brand Palette
# Gruvbox-anchored dark palette with copper-orange accent and maroon pop.
# Drop-in compatible with gruv.nix — all token names match.
# Use for: business tools, estimator PWA dev, any HWC-context theming.

{ osConfig ? {} }:
{
  name = "hwc";

  # --- Background Hierarchy ---
  # HWC runs slightly blue-shifted from pure gruvbox — warmer than Nord, cooler than gruvbox.
  bg0      = "1d2021";  # Deepest: modals, masks, deepest overlays  (same as gruv bg0)
  bg1      = "23282d";  # Main: primary background                   (HWC specific — blue-shifted gruvbox)
  bg2      = "2c3338";  # Elevated: sidebars, inactive tabs          (midpoint between bg1 and bg3)
  bg3      = "32373c";  # Highest: active elements, buttons, borders

  # Legacy aliases (compatible with gruv.nix consumers)
  bg       = "23282d";  # → bg1
  bgAlt    = "2c3338";  # → bg2
  bgDark   = "1d2021";  # → bg0
  surface0 = "282d32";  # intermediate shade
  surface1 = "2c3338";  # intermediate shade
  surface2 = "32373c";  # intermediate shade

  # --- Foreground Hierarchy ---
  # Cream tones — exact gruvbox fg0/fg1 at top, slightly warmer mid-tones.
  fg0      = "ebdbb2";  # Brightest: headings, emphasis, key info    (same as gruv fg0)
  fg1      = "d5c4a1";  # Normal: body text, primary content         (HWC text-body — slightly cooler than gruv d4be98)
  fg2      = "a7aaad";  # Dimmed: secondary text, labels             (HWC text-muted — more neutral than gruv bdae93)
  fg3      = "50626f";  # Muted: disabled, comments, dividers        (blue-grey muted)

  # Legacy aliases
  fg       = "d5c4a1";  # → fg1
  fgDim    = "a7aaad";  # → fg2
  muted    = "50626f";  # → fg3

  # --- Primary Accents ---
  # Orange is the Heartwood signature. Red is the pop accent — one element per layout max.
  accent     = "cf995f"; # Copper-orange: primary accent — rules, separators, highlights
  accentAlt  = "9d0006"; # Dark maroon: pop accent — QR borders, single callout elements
  accent2    = "0085ba"; # Blue: digital-only — links and interactive states (web only, not print)

  # --- Semantic Status Colors ---
  # Mapped to HWC-appropriate tones. Orange family for warnings, maroon for errors.
  success       = "a9b665"; # Green: success states          (carried from gruvbox — no HWC equivalent)
  successBright = "b8bb26"; # Bright green: emphasis
  successDim    = "89b482"; # Teal green: subtle

  warning       = "cf995f"; # Copper-orange: warnings        (HWC accent-orange doubles as warning)
  warningBright = "fcbb74"; # Light amber: urgent

  error         = "9d0006"; # Dark maroon: errors            (HWC accent-red)
  errorBright   = "cc241d"; # Bright red: critical
  errorDim      = "661a1a"; # Deep red: broken/invalid

  info          = "0085ba"; # Blue: info/help                (HWC accent-blue)

  # Legacy aliases
  good  = "a9b665";  # → success
  warn  = "cf995f";  # → warning
  crit  = "9d0006";  # → error

  # --- UI Element Colors ---
  # Selection & Marking
  selection   = "cf995f"; # Orange selection
  selectionFg = "1d2021"; # Text on selection (dark bg for contrast)
  selectionBg = "cf995f"; # Selection background
  marked      = "9d0006"; # Marked items (maroon)
  markedAlt   = "0085ba"; # Alt marked color (blue)

  # Interactive Elements
  cursorColor = "d5c4a1"; # Text cursor — body cream
  caret       = "d5c4a1"; # Caret/insertion point
  link        = "0085ba"; # Hyperlinks — blue (digital only)
  linkHover   = "cf995f"; # Hovered links — orange

  # Borders & Separators
  border      = "32373c"; # Main borders        (bg3)
  borderDim   = "2c3338"; # Subtle borders      (bg2)
  borderBright= "cf995f"; # Emphasized borders  (orange accent)
  separator   = "cf995f"; # UI separators       (orange — the Heartwood rule)

  # Progress & Loading
  progress    = "cf995f"; # Progress bar fill   (orange)
  progressBg  = "2c3338"; # Progress bar background

  # --- Surfaces ---
  surface     = "f0f0f1"; # Light surface — reversed sections, print white areas
  border-light = "c3c4c7"; # Borders on light surfaces

  # --- ANSI 16 (terminal adapters — Kitty, WezTerm, etc.) ---
  # Gruvbox base where no HWC-specific equivalent exists.
  ansi = {
    black   = "23282d";  # bg1 — slightly blue gruvbox
    red     = "9d0006";  # HWC maroon
    green   = "a9b665";  # gruvbox green (no HWC equivalent)
    yellow  = "cf995f";  # HWC copper-orange
    blue    = "0085ba";  # HWC accent-blue
    magenta = "661a1a";  # deep maroon
    cyan    = "50626f";  # HWC fg3 blue-grey
    white   = "d5c4a1";  # HWC text-body cream

    brightBlack   = "32373c";  # bg3
    brightRed     = "cc241d";  # brighter red
    brightGreen   = "b8bb26";  # gruvbox bright green
    brightYellow  = "fcbb74";  # light amber
    brightBlue    = "30ceff";  # HWC accent-cyan (from site palette)
    brightMagenta = "9d0006";  # maroon — same as red tier
    brightCyan    = "0085ba";  # HWC blue
    brightWhite   = "ebdbb2";  # HWC text-primary — brightest cream
  };

  # --- Hyprland helpers ---
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft   = "aa";
    faint  = "66";
  };

  hypr = {
    orange = "cf995f";  # Primary accent for borders/active window
    red    = "9d0006";  # Pop accent for urgent/marked
    muted  = "32373c";  # bg3 for inactive
  };

  # --- Pointer theme config ---
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
