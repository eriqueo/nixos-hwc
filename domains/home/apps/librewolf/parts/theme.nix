{ lib, config, ... }:

let
  # chosen palette name (fallback to deep-nord)
  paletteName = if config.hwc.home.theme.palette != null then config.hwc.home.theme.palette else "deep-nord";

  # path from apps/librewolf/parts/ -> domains/home/theme/palettes/
  palettePath = ../../../theme/palettes/${paletteName}.nix;

  palette = if builtins.pathExists palettePath
    then import palettePath {}
    else import ../../../theme/palettes/deep-nord.nix {};

  # prefix '#' if hex doesn't already include it
  hex = colour: if builtins.substring 0 1 colour == "#" then colour else "#" + colour;

  # safe lookups with Gruvbox-friendly fallbacks
  get = attr: fallback: if palette ? ${attr} then palette.${attr} else fallback;

  bgMain    = get "bg1" (get "bg" "282828");
  bgSurface = get "bg2" bgMain;
  bgRaised  = get "bg3" bgSurface;
  fgMain    = get "fg1" (get "fg" "d4be98");
  fgDim     = get "fg2" (get "fgDim" fgMain);
  accent    = get "accent" fgMain;
  accentAlt = get "accentAlt" accent;
  muted     = get "muted" fgDim;
  borderCol = if palette ? border then palette.border else bgSurface;
  selection = get "selection" accent;
  selectionFg = get "selectionFg" bgMain;
in
{
  userChrome = ''
    :root {
      --hwc-bg: ${hex bgMain};
      --hwc-surface: ${hex bgSurface};
      --hwc-raised: ${hex bgRaised};
      --hwc-fg: ${hex fgMain};
      --hwc-fg-dim: ${hex fgDim};
      --hwc-accent: ${hex accent};
      --hwc-accent-strong: ${hex accentAlt};
      --hwc-muted: ${hex muted};
      --hwc-border: ${hex borderCol};
    }

    /* Toolbar and chrome */
    #navigator-toolbox,
    #TabsToolbar,
    #nav-bar {
      background-color: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border: none !important;
      box-shadow: inset 0 -1px 0 var(--hwc-border);
    }

    #urlbar, #searchbar {
      background-color: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
      box-shadow: none !important;
    }

    #urlbar[focused="true"] {
      border-color: var(--hwc-accent) !important;
      background-color: var(--hwc-raised) !important;
    }

    #urlbar-input, .urlbar-input-box {
      color: var(--hwc-fg) !important;
    }

    /* Urlbar dropdown / suggestions */
    #urlbar-results,
    .urlbarView,
    .urlbarView-body,
    .urlbarView-results {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
    }

    .urlbarView-row {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border-bottom: 1px solid var(--hwc-border) !important;
    }

    .urlbarView-row:hover,
    .urlbarView-row[selected],
    .urlbarView-row:is([selected], :hover) .urlbarView-row-inner {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
    }

    .urlbarView-row .urlbarView-title,
    .urlbarView-row .urlbarView-url {
      color: var(--hwc-fg) !important;
    }

    .urlbarView-row .urlbarView-url {
      color: var(--hwc-accent) !important;
    }

    .urlbarView-row .urlbarView-action {
      color: var(--hwc-fg-dim) !important;
    }

    .urlbarView-separator,
    .urlbarView-header {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg-dim) !important;
    }

    /* Urlbar dropdown outline */
    #urlbar-results,
    .urlbarView {
      border: 1px solid var(--hwc-border) !important;
    }

    /* Tabs */
    .tabbrowser-tab .tab-background {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg-dim) !important;
      border: 1px solid transparent !important;
    }

    .tabbrowser-tab[selected="true"] .tab-background {
      background: var(--hwc-raised) !important;
      color: var(--hwc-fg) !important;
      border-color: var(--hwc-accent) !important;
      box-shadow: inset 0 -1px 0 var(--hwc-accent-strong);
    }

    .tabbrowser-tab:not([selected]) .tab-background:hover {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
    }

    .tabbrowser-tab:not([selected]) .tab-label {
      color: var(--hwc-fg-dim) !important;
    }

    toolbarbutton {
      color: var(--hwc-fg) !important;
      fill: var(--hwc-fg) !important;
    }

    toolbarbutton:hover {
      background: var(--hwc-surface) !important;
      border-radius: 4px !important;
    }

    toolbarbutton[open="true"], toolbarbutton:active {
      background: var(--hwc-raised) !important;
    }

    /* Links inside chrome UI */
    a { color: var(--hwc-accent) !important; }

    /* Bookmarks toolbar */
    #PersonalToolbar {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border: none !important;
      box-shadow: inset 0 1px 0 var(--hwc-border);
    }

    #PersonalToolbar toolbarbutton,
    #PersonalToolbar .bookmark-item {
      color: var(--hwc-fg) !important;
      fill: var(--hwc-fg) !important;
    }

    #PersonalToolbar .bookmark-item:hover {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
    }

    /* Identity / lock / tracking icons and badges */
    #identity-box,
    #tracking-protection-icon-container,
    #tracking-protection-icon,
    #identity-icon,
    #page-action-buttons .urlbar-icon,
    #star-button-box,
    #pocket-button-box {
      background: transparent !important;
      color: var(--hwc-fg) !important;
      fill: var(--hwc-fg) !important;
    }

    #identity-box:hover,
    #identity-box:focus-within,
    #tracking-protection-icon-container:hover,
    #tracking-protection-icon-container:focus-within {
      background: var(--hwc-surface) !important;
      border-radius: 4px !important;
    }

    /* URL bar origin label pill (e.g., LibreWolf/about:preferences) */
    #identity-icon-labels,
    #identity-icon {
      color: var(--hwc-fg) !important;
      fill: var(--hwc-fg) !important;
    }

    #identity-box[pageproxystate="valid"] > #identity-icon-box {
      background: var(--hwc-surface) !important;
      border: 1px solid var(--hwc-border) !important;
      border-radius: 6px !important;
    }
  '';

  userContent = ''
    :root {
      --hwc-bg: ${hex bgMain};
      --hwc-surface: ${hex bgSurface};
      --hwc-fg: ${hex fgMain};
      --hwc-accent: ${hex accent};
      --hwc-muted: ${hex muted};
      --hwc-border: ${hex borderCol};
    }

    /* Basic page defaults */
    body { background-color: var(--hwc-bg) !important; color: var(--hwc-fg) !important; }
    a, a:visited { color: var(--hwc-accent) !important; }
    input, textarea, select {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
    }
    ::selection { background: ${hex selection} !important; color: ${hex selectionFg} !important; }
  '';
}
