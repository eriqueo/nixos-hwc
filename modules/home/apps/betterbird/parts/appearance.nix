# Betterbird • Appearance part
# Pure theming (CSS) driven by the global palette.
{ lib, pkgs, config, ... }:

let
  C = config.hwc.home.theme.colors or {};
  toCss = c: if c == null then "#888888" else "#" + (lib.removePrefix "#" c);

  bg      = toCss (C.bg or "282828");
  fg      = toCss (C.fg or "ebdbb2");
  accent  = toCss (C.accent or "83a598");
  hilite  = toCss (C.warn or "fabd2f");
  border  = toCss (C.border or "504945");
  surface = toCss (C.surface0 or "323232");
in
{
  # appearance contributes only file drops under the user’s profile path
  files = profileBase: {
    # Classic UI tweaks (toolbars, trees, etc.)
    "${profileBase}/chrome/userChrome.css".text = ''
      @namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");

      :root {
        --bb-bg:        ${bg};
        --bb-fg:        ${fg};
        --bb-accent:    ${accent};
        --bb-hilite:    ${hilite};
        --bb-border:    ${border};
        --bb-surface:   ${surface};
      }

      /* Folder pane */
      #folderTree,
      #folderPaneBox,
      treechildren {
        background-color: var(--bb-bg) !important;
        color: var(--bb-fg) !important;
      }

      /* Thread list */
      #threadTree treechildren::-moz-tree-row(selected, focus) {
        background-color: var(--bb-hilite) !important;
        color: ${bg} !important;
      }
      #threadTree treechildren::-moz-tree-cell-text {
        color: var(--bb-fg) !important;
      }

      /* Toolbars */
      .toolbarbutton-1 {
        border: 1px solid var(--bb-border) !important;
        background-color: var(--bb-surface) !important;
        color: var(--bb-fg) !important;
      }

      /* Compose window */
      .compose-window,
      #compose-toolbox,
      #attachmentBucket {
        background-color: var(--bb-bg) !important;
        color: var(--bb-fg) !important;
      }
    '';

    # Content styling inside messages / reader
    "${profileBase}/chrome/userContent.css".text = ''
      :root {
        color-scheme: dark;
      }
      body, html {
        background: ${bg} !important;
        color: ${fg} !important;
      }
      a { color: ${accent} !important; }
      ::selection { background: ${hilite}; color: ${bg}; }
    '';
  };
}
