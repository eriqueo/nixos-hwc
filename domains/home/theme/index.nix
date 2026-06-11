# domains/home/theme/index.nix
#
# THEME ROOT — Single entry point for theming in Home Manager.
# Materializes the selected palette as token sets (colors, cursor) and
# declares the look-and-feel surface (icons, gtkTheme, typography, fonts)
# that templates/ and app parts consume.
#
# DEPENDENCIES (Upstream):
#   - ./palettes/*.nix      (tokens)
#   - ./templates/gtk.nix   (palette -> GTK 2/3/4)
#   - ./fonts/index.nix     (font packages + mono/ui name tokens)
#
# USED BY (Downstream):
#   - domains/home/apps/* parts via the guarded read
#     (config.hwc.home.theme or {}).colors or {}
#
{ config, lib, osConfig ? {}, ... }:

let
  palettes = rec {
    deep-nord = import ./palettes/deep-nord.nix { };
    hwc       = import ./palettes/hwc.nix { };
    gruv      = import ./palettes/gruv.nix { };
  };

  activePalette = palettes.${config.hwc.home.theme.palette};
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.theme = {
    palette = lib.mkOption {
      type = lib.types.enum [ "deep-nord" "gruv" "hwc" ];
      default = "hwc";
      description = "Active theme palette (single source of truth).";
    };

    graphical = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this machine has a graphical session. When false (headless),
        the GUI-only XCursor theme (~846 MB) is not installed and the GTK
        pointer-cursor wiring is skipped. Palette colors still apply for
        shell/CLI. Graphical machines keep the default (true); headless
        machines set false in their machine home one-off (cf.
        theme.fonts.enable).
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Materialized color tokens from selected palette.";
    };

    cursor = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Pointer cursor tokens ({ size, xcursor = { name, package }, ... }).
        Materialized from the palette's cursor block. Consumed by
        templates/gtk.nix and hyprland/parts/session.nix.
      '';
    };

    icons = lib.mkOption {
      type = lib.types.attrs;
      default = { name = "Papirus-Dark"; package = "papirus-icon-theme"; };
      description = "Icon theme tokens ({ name, package }). Consumed by templates/gtk.nix.";
    };

    gtkTheme = lib.mkOption {
      type = lib.types.attrs;
      default = { name = "Adwaita-dark"; package = "gnome-themes-extra"; };
      description = "GTK theme tokens ({ name, package }). Consumed by templates/gtk.nix.";
    };

    typography = lib.mkOption {
      type = lib.types.attrs;
      default = { uiFont = "Inter"; uiSize = 11; };
      description = "UI typography tokens ({ uiFont, uiSize }). Consumed by templates/gtk.nix.";
    };
  };

  imports = [
    ./templates/gtk.nix
    ./fonts/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {
    # Materialize the selected palette as a read-only token set for apps.
    hwc.home.theme.colors = activePalette;

    # Pointer cursor from the palette. Only size + xcursor are wired:
    # the palettes' hyprcursor blocks reference an asset tree
    # (modules/home/theme/assets/...) that no longer exists in the repo —
    # wiring them would break eval. Hyprland falls back to XCursor
    # rendering, same as before. (Backlog: restore hyprcursor assets.)
    hwc.home.theme.cursor = lib.mkDefault {
      size    = (activePalette.cursor or {}).size or 24;
      xcursor = (activePalette.cursor or {}).xcursor or {};
    };

    # Qt apps follow the GTK dark theme.
    qt = {
      enable = true;
      platformTheme.name = "gtk3";
    };
  };
}
