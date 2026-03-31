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
  bg1      = "282828";  # Main: primary background                   (pure gruvbox — neutral, no blue shift)
  bg2      = "2c3338";  # Elevated: sidebars, inactive tabs          (midpoint between bg1 and bg3)
  bg3      = "32373c";  # Highest: active elements, buttons, borders

  # Legacy aliases (compatible with gruv.nix consumers)
  bg       = "282828";  # → bg1
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
  accent     = "d08770"; # Copper-orange: primary accent — rules, separators, highlights
  accentAlt  = "bf616a"; # Muted red: pop accent — readable on dark bg (Nord11)
  accent2    = "5e81ac"; # Blue: matches info — unified blue across all apps

  # --- Semantic Status Colors ---
  # Mapped to HWC-appropriate tones. Gruvbox/Nord hybrid — muted, readable on dark bg.
  success       = "a3be8c"; # Sage green: success states     (Nord14 — muted, no neon)
  successBright = "b4c89a"; # Brighter sage: emphasis
  successDim    = "8aab78"; # Dimmed sage: subtle

  warning       = "cf995f"; # Copper-orange: warnings        (HWC accent-orange doubles as warning)
  warningBright = "fcbb74"; # Light amber: urgent

  error         = "bf616a"; # Muted red: errors              (Nord11 — readable on dark bg)
  errorBright   = "d08080"; # Soft coral: critical
  errorDim      = "915252"; # Dark muted red: broken/invalid

  info          = "5e81ac"; # Blue: info/help                (HWC accent-blue)

  # Legacy aliases
  good  = "a3be8c";  # → success
  warn  = "cf995f";  # → warning
  crit  = "bf616a";  # → error

  # --- UI Element Colors ---
  # Selection & Marking
  selection   = "434c5e"; # Nord blue-grey selection (visible on dark bg)
  selectionFg = "ebdbb2"; # Bright cream text on selection
  selectionBg = "434c5e"; # Nord blue-grey selection
  marked      = "bf616a"; # Marked items (nord red)
  markedAlt   = "5e81ac"; # Alt marked color (unified blue)

  # Interactive Elements
  cursorColor = "d5c4a1"; # Text cursor — body cream
  caret       = "d5c4a1"; # Caret/insertion point
  link        = "5e81ac"; # Hyperlinks — unified blue (info)
  linkHover   = "cf995f"; # Hovered links — orange

  # Borders & Separators
  border      = "32373c"; # Main borders        (bg3)
  borderDim   = "2c3338"; # Subtle borders      (bg2)
  borderBright= "cf995f"; # Emphasized borders  (orange accent)
  separator   = "cf995f"; # UI separators       (orange — the Heartwood rule)

  # Progress & Loading
  progress    = "cf995f"; # Progress bar fill   (orange)
  progressBg  = "2c3338"; # Progress bar background

  # --- File Type Colors (for file managers — yazi, thunar, etc.) ---
  fileImage    = "cf995f"; # Orange: images      (HWC accent)
  fileMedia    = "fcbb74"; # Amber: audio/video
  fileArchive  = "bf616a"; # Muted red: archives/compressed
  fileDocument = "d5c4a1"; # Cream: documents/PDFs
  fileCode     = "5e81ac"; # Blue: source code (unified blue)
  fileExec     = "a3be8c"; # Sage: executables   (Nord14)
  fileOrphan   = "915252"; # Dark red: broken links
  fileDir      = "ebdbb2"; # Bright cream: directories

  # --- Surfaces ---
  surface     = "f0f0f1"; # Light surface — reversed sections, print white areas
  border-light = "c3c4c7"; # Borders on light surfaces

  # --- ANSI 16 (terminal adapters — Kitty, WezTerm, etc.) ---
  # Canonical gruvbox dark — verbatim from the official palette.
  # HWC brand accents live in UI tokens above. ANSI slots are for terminal
  # output readability, not brand expression.
  ansi = {
    black   = "282828";  # bg family
    red     = "bf616a";  # error family
    green   = "a3be8c";  # success family
    yellow  = "cf995f";  # warning family
    blue    = "5e81ac";  # info family
    magenta = "b16286";  # purple
    cyan    = "8aab78";  # success-dim family
    white   = "a89984";  # fg muted

    brightBlack   = "928374";  # fg3
    brightRed     = "d08080";  # errorBright family
    brightGreen   = "b4c89a";  # successBright family
    brightYellow  = "fcbb74";  # warningBright family
    brightBlue    = "81a1c1";  # info-bright family
    brightMagenta = "d3869b";  # purple bright
    brightCyan    = "a3be8c";  # success family
    brightWhite   = "ebdbb2";  # fg0
  };

  # --- Hyprland helpers ---
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft   = "aa";
    faint  = "66";
  };

  hypr = {
    orange = "d08770";  # Primary accent for borders/active window
    red    = "bf616a";  # Pop accent for urgent/marked (Nord11)
    muted  = "81a1c1";  # bg3 for inactive
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
