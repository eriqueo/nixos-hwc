# modules/home/theme/adapters/gtk.nix
# GTK Theme Adapter (v7 — palette -> GTK 2/3/4 + assets, HM-owned)
{ config, lib, pkgs, ... }:
let
  # ----------------------------
  # Palette tokens (with defaults)
  # ----------------------------
  colors = config.hwc.home.theme.colors or {};
  cursor = config.hwc.home.theme.cursor or {};
  xcur   = cursor.xcursor or {};
  cursSize = cursor.size or 24;

  icons  = config.hwc.home.theme.icons or {
    name    = "Papirus-Dark";
    package = "papirus-icon-theme";
  };

  # Optional: explicit GTK theme token (name+pkg); defaults to Adwaita-dark
  gtkThemeTok = config.hwc.home.theme.gtkTheme or {
    name    = "Adwaita-dark";
    package = "gnome-themes-extra";
  };

  typo = config.hwc.home.theme.typography or {};
  uiFontName = typo.uiFont or "Inter";
  uiFontSize = toString (typo.uiSize or 11);

  # ----------------------------
  # Helpers
  # ----------------------------
  pkgByName = name:
    if lib.hasAttr name pkgs then builtins.getAttr name pkgs else pkgs.adwaita-icon-theme;

  toGtk = colorStr:
    if colorStr == null then "#888888" else "#" + (lib.removePrefix "#" colorStr);

  # ----------------------------
  # Resolved packages and names
  # ----------------------------
  gtkPkg   = pkgByName (gtkThemeTok.package or "gnome-themes-extra");
  iconPkg  = pkgByName (icons.package or "papirus-icon-theme");
  xcurPkg  = pkgByName (xcur.package or "adwaita-icon-theme");

  gtkThemeName  = gtkThemeTok.name or "Adwaita-dark";
  iconThemeName = icons.name or "Papirus-Dark";
  xcurName      = xcur.name or "Adwaita";

  # ----------------------------
  # Derived colors for CSS
  # ----------------------------
  bg     = toGtk (colors.bg or null);
  bgAlt  = toGtk (colors.bgAlt or null);
  bgDark = toGtk (colors.bgDark or null);
  fg     = toGtk (colors.fg or null);
  accent = toGtk (colors.accent or null);
  muted  = toGtk (colors.muted or null);

  # ----------------------------
  # GTK extra settings
  # ----------------------------
  gtk2Extra = ''
    gtk-theme-name = "${gtkThemeName}"
    gtk-icon-theme-name = "${iconThemeName}"
    gtk-cursor-theme-name = "${xcurName}"
    gtk-font-name = "${uiFontName} ${uiFontSize}"
  '';

  gtk3Extra = {
    gtk-theme-name = gtkThemeName;
    gtk-icon-theme-name = iconThemeName;
    gtk-cursor-theme-name = xcurName;
    gtk-font-name = "${uiFontName} ${uiFontSize}";
    gtk-application-prefer-dark-theme = true;
  };

  gtk4Extra = {
    gtk-theme-name = gtkThemeName;
    gtk-icon-theme-name = iconThemeName;
    gtk-cursor-theme-name = xcurName;
    gtk-font-name = "${uiFontName} ${uiFontSize}";
    gtk-application-prefer-dark-theme = true;
  };

  # ----------------------------
  # Palette-driven CSS
  # ----------------------------
  gtk3Css = ''
    /* Minimal GTK3 palette bridge */
    window, .background { background-color: ${bg}; color: ${fg}; }
    .sidebar, .sidebar view { background-color: ${bgAlt}; color: ${fg}; }
    headerbar { background-color: ${bgAlt}; color: ${fg}; }
    entry, textview, treeview, .view {
      background-color: ${bgDark}; color: ${fg}; border: 1px solid ${muted};
    }
    button { background-color: ${bgAlt}; color: ${fg}; border: 1px solid ${muted}; }
    button:hover, .suggested-action, .destructive-action {
      background-color: ${accent}; color: ${bg};
    }
    *:selected { background-color: ${accent}; color: ${bg}; }
  '';

  # GTK4 uses the same tokens; keep it small (most apps theme themselves)
  gtk4Css = ''
    /* Minimal GTK4 palette bridge */
    window, .background { background-color: ${bg}; color: ${fg}; }
    headerbar, .titlebar { background-color: ${bgAlt}; color: ${fg}; }
    button { background-color: ${bgAlt}; color: ${fg}; border: 1px solid ${muted}; }
    button:hover { background-color: ${accent}; color: ${bg}; }
    selection, *.selection { background-color: ${accent}; color: ${bg}; }
  '';

  # ----------------------------
  # One canonical settings value for downstream use
  # ----------------------------
  settingsDefault = {
    gtk = {
      enable = true;
      theme = {
        name = gtkThemeName;
        package = gtkPkg;
      };
      iconTheme = {
        name = iconThemeName;
        package = iconPkg;
      };
      cursorTheme = {
        name = xcurName;
        package = xcurPkg;
        size = cursSize;
      };
      font = {
        name = uiFontName;
        size = lib.toInt uiFontSize;
      };
      gtk2.extraConfig = gtk2Extra;
      gtk3.extraConfig = gtk3Extra;
      gtk4.extraConfig = gtk4Extra;
    };

    # Palette-driven CSS drops
    xdg.configFile."gtk-3.0/gtk.css".text = gtk3Css;
    xdg.configFile."gtk-4.0/gtk.css".text = gtk4Css;
  };
in
{
  # Expose a stable value other adapters can read/merge if they want.
  options.hwc.home.theme.adapters.gtk.settings = lib.mkOption {
    type = lib.types.attrs;
    description = "GTK 2/3/4 settings derived from the active palette (theme, icons, cursor, font, css).";
    default = settingsDefault;
  };

  # Apply those settings in HM, and ensure assets are installed.
  config = lib.mkMerge [
    settingsDefault
    {
      # Ensure GTK/Qt apps use the XCursor from the palette,
      # and the assets are present in the user profile.
      home.pointerCursor = {
        name = xcurName;
        package = xcurPkg;
        size = cursSize;
        gtk.enable = true;
      };

      home.packages = (config.home.packages or []) ++ [
        xcurPkg
        iconPkg
        gtkPkg
      ];
    }
  ];
}
