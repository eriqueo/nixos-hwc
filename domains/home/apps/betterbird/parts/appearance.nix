{ lib, pkgs, config, osConfig ? {}, ...}:

let
  # Import theme palette directly
  palette = import ../../../theme/palettes/deep-nord.nix {};
  
  # Convert palette colors to CSS format
  bg      = "#${palette.bg}";
  fg      = "#${palette.fg}";
  accent  = "#${palette.accent}";
  hilite  = "#${palette.warn}";
  border  = "#${palette.border}";
  surface = "#${palette.surface0}";
in
{
  files = profileBase: {
    "${profileBase}/chrome/userChrome.css".text = ''
      @namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");

      :root {
        --bb-bg:      ${bg};
        --bb-fg:      ${fg};
        --bb-accent:  ${accent};
        --bb-hilite:  ${hilite};
        --bb-border:  ${border};
        --bb-surface: ${surface};
      }

      #folderTree, #folderPaneBox, treechildren {
        background-color: var(--bb-bg) !important;
        color: var(--bb-fg) !important;
      }

      #threadTree treechildren::-moz-tree-row(selected, focus) {
        background-color: var(--bb-hilite) !important;
        color: ${bg} !important;
      }
      #threadTree treechildren::-moz-tree-cell-text {
        color: var(--bb-fg) !important;
      }

      .toolbarbutton-1 {
        border: 1px solid var(--bb-border) !important;
        background-color: var(--bb-surface) !important;
        color: var(--bb-fg) !important;
      }

      .compose-window, #compose-toolbox, #attachmentBucket {
        background-color: var(--bb-bg) !important;
        color: var(--bb-fg) !important;
      }
    '';

    "${profileBase}/chrome/userContent.css".text = ''
      :root { color-scheme: dark; }
      body, html { background: ${bg} !important; color: ${fg} !important; }
      a { color: ${accent} !important; }
      ::selection { background: ${hilite}; color: ${bg}; }
    '';
  };
}