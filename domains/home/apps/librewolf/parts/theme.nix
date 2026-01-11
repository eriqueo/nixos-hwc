{ lib, config, ... }:

let
  # Determine palette
  paletteName =
    let chosen = lib.attrByPath [ "hwc" "home" "theme" "palette" ] null config;
    in if chosen != null then chosen else "deep-nord";

  palettePath = ../../../theme/palettes/${paletteName}.nix;

  palette = if builtins.pathExists palettePath
    then import palettePath {}
    else import ../../../theme/palettes/deep-nord.nix {};

  # Helper functions
  hex = colour: if builtins.substring 0 1 colour == "#" then colour else "#" + colour;
  get = attr: fallback: if palette ? ${attr} then palette.${attr} else fallback;

  # Variable Mapping
  bgMain      = get "bg1" (get "bg" "282828");
  bgSurface   = get "bg2" bgMain;
  bgRaised    = get "bg3" bgSurface;
  fgMain      = get "fg1" (get "fg" "d4be98");
  fgDim       = get "fg2" (get "fgDim" fgMain);
  accent      = get "accent" fgMain;
  accentAlt   = get "accentAlt" accent;
  muted       = get "muted" fgDim;
  borderCol   = if palette ? border then palette.border else bgSurface;
  
  # Variables for selection styling
  selection   = get "selection" accent;
  selectionFg = get "selectionFg" bgMain;

  commonVars = ''
    --hwc-bg: ${hex bgMain};
    --hwc-surface: ${hex bgSurface};
    --hwc-raised: ${hex bgRaised};
    --hwc-fg: ${hex fgMain};
    --hwc-fg-dim: ${hex fgDim};
    --hwc-accent: ${hex accent};
    --hwc-accent-strong: ${hex accentAlt};
    --hwc-muted: ${hex muted};
    --hwc-border: ${hex borderCol};
  '';
in
{
  userChrome = ''
    :root {
      ${commonVars}
      --arrowpanel-background: var(--hwc-raised) !important;
      --arrowpanel-color: var(--hwc-fg) !important;
      --arrowpanel-border-color: var(--hwc-border) !important;
    }

    #navigator-toolbox, #TabsToolbar, #nav-bar {
      background-color: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border: none !important;
      box-shadow: inset 0 -1px 0 var(--hwc-border);
    }

    #urlbar, #searchbar {
      background-color: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
    }

    .tabbrowser-tab[selected="true"] .tab-background {
      background: var(--hwc-raised) !important;
      border-color: var(--hwc-accent) !important;
    }
  '';

  userContent = ''
    :root {
      ${commonVars}
      /* Hijack JobTread's internal Tailwind variables */
      --color-gray-50: var(--hwc-bg) !important;
      --color-gray-100: var(--hwc-surface) !important;
      --color-gray-200: var(--hwc-border) !important;
      --color-gray-800: var(--hwc-fg) !important;
      --color-gray-900: var(--hwc-fg) !important;
      --color-white: var(--hwc-bg) !important;
    }

    /* Global selection */
    ::selection { 
      background: ${hex selection} !important; 
      color: ${hex selectionFg} !important; 
    }

    @-moz-document domain("app.jobtread.com") {
      
      /* 1. Background Overrides */
      html, body, 
      [class*="bg-white"], 
      [class*="bg-gray-50"], 
      [class*="bg-slate-50"] {
        background-color: var(--hwc-bg) !important;
        color: var(--hwc-fg) !important;
      }

      /* 2. Surface & Card Areas */
      [class*="bg-gray-100"], 
      .MuiPaper-root, 
      .jt-card,
      header[class*="MuiAppBar"] {
        background-color: var(--hwc-surface) !important;
        color: var(--hwc-fg) !important;
        border-color: var(--hwc-border) !important;
      }

      /* 3. Text & Typography */
      [class*="text-gray-"], 
      [class*="text-slate-"], 
      .MuiTypography-root {
        color: var(--hwc-fg) !important;
      }

      /* 4. Borders - Must override Tailwind's layer utilities */
      *, :after, :before, ::backdrop {
        border-color: var(--hwc-border) !important;
      }
      
      /* Specifically target Tailwind border utilities */
      [class*="border-"],
      [class*="divide-"],
      .border-b, .border-t, .border-l, .border-r,
      .border, .divide-y > *, .divide-x > * {
        border-color: var(--hwc-border) !important;
      }
      
      /* 5. Table-specific borders */
      table, thead, tbody, tr, td, th {
        border-color: var(--hwc-border) !important;
        background-color: transparent !important;
      }

      /* 6. Navigation & Interaction */
      nav a:hover, 
      nav a[class*="active"],
      [class*="cursor-pointer"]:hover {
        background-color: var(--hwc-raised) !important;
      }

      /* 7. Inputs & Forms */
      input, select, textarea, .MuiInputBase-root {
        background-color: var(--hwc-surface) !important;
        color: var(--hwc-fg) !important;
        border: 1px solid var(--hwc-border) !important;
      }

      /* 8. Icons */
      svg, [stroke="currentColor"] {
        color: var(--hwc-fg) !important;
        stroke: var(--hwc-fg) !important;
        fill: currentColor;
      }
       /* Table-specific borders */
      table, thead, tbody, tr, td, th {
        border-color: var(--hwc-border) !important;
      }
    }
  '';
}
