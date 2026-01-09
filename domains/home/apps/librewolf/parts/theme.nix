{ lib, config, ... }:

let
  # chosen palette name (fallback to deep-nord)
  paletteName =
    let chosen = lib.attrByPath [ "hwc" "home" "theme" "palette" ] null config;
    in if chosen != null then chosen else "deep-nord";

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

    .urlbarView-body-inner {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
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

    /* --- More Robust Popups, Menus, and Tooltips --- */
    :root {
      --arrowpanel-background: var(--hwc-raised) !important;
      --arrowpanel-color: var(--hwc-fg) !important;
      --arrowpanel-border-color: var(--hwc-border) !important;
    }

    menupopup,
    panel,
    .panel-subview-body {
      --panel-background: var(--hwc-raised) !important;
      --panel-color: var(--hwc-fg) !important;
      --panel-border-color: var(--hwc-border) !important;
      background: var(--panel-background) !important;
      color: var(--panel-color) !important;
      border: 1px solid var(--panel-border-color) !important;
    }

    .panel-header,
    .panel-footer {
      background: var(--hwc-surface) !important;
      border-bottom: 1px solid var(--hwc-border) !important;
    }

    menu,
    menuitem,
    .menu-iconic,
    .menuitem-iconic {
      -moz-appearance: none !important;
      background: transparent !important;
      color: var(--hwc-fg) !important;
    }

    menu:hover,
    menuitem:hover,
    .menu-iconic:hover,
    .menuitem-iconic:hover {
      background-color: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
    }

    menu[disabled="true"],
    menuitem[disabled="true"] {
      color: var(--hwc-muted) !important;
    }

    menuseparator {
      -moz-appearance: none !important;
      background: var(--hwc-border) !important;
      border: none !important;
      padding: 0 !important;
      margin: 4px 8px !important;
      height: 1px !important;
    }

    /* Tooltips */
    tooltip,
    #tooltip,
    #customization-palette-tooltip,
    #urlbar-tooltip,
    .tooltip-label {
      -moz-appearance: none !important;
      background: var(--hwc-raised) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
    }
    /* --- End Robust Popups --- */

    /* DevTools: enforce dark theme for panels and popups */
    :root {
      --theme-body-background: var(--hwc-bg) !important;
      --theme-body-color: var(--hwc-fg) !important;
      --theme-toolbar-background: var(--hwc-bg) !important;
      --theme-toolbar-color: var(--hwc-fg) !important;
      --theme-tab-toolbar-background: var(--hwc-bg) !important;
      --theme-selection-background: var(--hwc-accent) !important;
      --theme-selection-color: var(--hwc-raised) !important;
    }

    .theme-dark,
    .devtools-toolbox,
    .webconsole-output,
    .theme-body,
    .theme-toolbar,
    .toolbox-tabbar,
    .devtools-sidepanel,
    .ruleview,
    .grid-container,
    .animation-container,
    .inspector-tabpanel,
    .tabview-arrowscrollbox,
    .tabbar,
    .theme-sidebar,
    .theme-toolbar-panel {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border-color: var(--hwc-border) !important;
    }

    .theme-dark input,
    .theme-dark textarea,
    .theme-dark select,
    .theme-dark .textbox-input,
    .theme-dark .devtools-searchinput {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
    }

    .theme-dark .toolbarbutton-1,
    .theme-dark .devtools-button {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border-color: var(--hwc-border) !important;
    }

    .theme-dark .toolbarbutton-1:hover,
    .theme-dark .devtools-button:hover,
    .theme-dark .devtools-button[checked="true"] {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
      border-color: var(--hwc-accent) !important;
    }

    /* DevTools settings panels and menus */
    .theme-dark menupopup,
    .theme-dark panel,
    .theme-dark .panel-subview-body,
    .theme-dark .devtools-option-toolbar {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
      border: 1px solid var(--hwc-border) !important;
    }

    .theme-dark menuitem,
    .theme-dark menu {
      background: var(--hwc-bg) !important;
      color: var(--hwc-fg) !important;
    }

    .theme-dark menuitem:hover,
    .theme-dark menu:hover {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
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

    /* In-page dropdowns */
    option, optgroup {
      background: var(--hwc-surface) !important;
      color: var(--hwc-fg) !important;
    }
    option:hover, option:checked {
      background: var(--hwc-accent) !important;
      color: ${hex selectionFg} !important;
    }
  '';
}
