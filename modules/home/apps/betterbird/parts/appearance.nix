# nixos-hwc/modules/home/betterbird/parts/appearance.nix
#
# Betterbird Appearance: Visual Styling & UI Customization
# Charter v5 compliant - Universal appearance domain for email client theming
#
# DEPENDENCIES (Upstream):
#   - None (UI styling configuration)
#
# USED BY (Downstream):
#   - modules/home/betterbird/default.nix
#
# USAGE:
#   let appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
#   in { home.file = appearance.files profileBase; }
#

{ lib, pkgs, config, ... }:

{
  #============================================================================
  # CONFIGURATION FILES - Visual styling and theme customization
  #============================================================================
  files = profileBase: {
    # Custom CSS for Betterbird/Thunderbird UI theming
    "${profileBase}/chrome/userChrome.css".text = ''
      @namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");

      /* Gruvbox Dark Theme Integration */
      :root {
        --inbox-bg: #282828;
        --inbox-text: #ebdbb2;
        --highlight: #fabd2f;
        --accent: #83a598;
        --border: #504945;
      }

      /* Message list styling */
      #threadTree treechildren::-moz-tree-row(selected, focus) {
        background-color: var(--highlight) !important;
        color: #282828 !important;
      }
      
      treechildren::-moz-tree-cell-text {
        color: var(--inbox-text) !important;
      }

      /* Folder pane styling */
      #folderTree treechildren::-moz-tree-row(selected, focus) {
        background-color: var(--accent) !important;
      }

      /* Toolbar and interface elements */
      .toolbarbutton-1 {
        border: 1px solid var(--border) !important;
      }

      /* Message composition window */
      .compose-window {
        background-color: var(--inbox-bg) !important;
        color: var(--inbox-text) !important;
      }
    '';
  };
}