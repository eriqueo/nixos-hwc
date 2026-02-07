# modules/home/theme/adapters/gtk.nix
# GTK Theme Adapter (v7 — palette -> GTK 2/3/4 + assets, HM-owned; no options, no recursion)
{ config, lib, pkgs, ... }:
let
  # ----------------------------
  # Palette tokens (with defaults)
  # ----------------------------
  T       = config.hwc.home.theme or {};
  colors  = T.colors or T;
  cursor  = T.cursor or {};
  xcur    = cursor.xcursor or {};
  cursSize = cursor.size or 24;

  icons = T.icons or {
    name    = "Papirus-Dark";
    package = "papirus-icon-theme";
  };

  gtkThemeTok = T.gtkTheme or {
    name    = "Adwaita-dark";
    package = "gnome-themes-extra";
  };

  typo         = T.typography or {};
  uiFontName   = typo.uiFont or "Inter";
  uiFontSizeInt = typo.uiSize or 11;            # keep as int for gtk.font.size
  uiFontSizeStr = toString uiFontSizeInt;       # string form for gtk2 extra

  # ----------------------------
  # Helpers
  # ----------------------------
  pkgByName = name:
    if (builtins.typeOf name == "string") && (lib.hasAttr name pkgs)
    then builtins.getAttr name pkgs
    else (pkgs.adwaita-icon-theme or pkgs.gnome.adwaita-icon-theme or null);

  toGtk = colorStr:
    if colorStr == null then "#888888" else "#" + (lib.removePrefix "#" colorStr);

  # ----------------------------
  # Resolved packages and names
  # ----------------------------
  gtkPkg        = pkgByName (gtkThemeTok.package or "gnome-themes-extra");
  iconPkg       = pkgByName (icons.package or "papirus-icon-theme");
  xcurPkg       = pkgByName (xcur.package or (if pkgs ? adwaita-icon-theme then "adwaita-icon-theme" else "gnome.adwaita-icon-theme"));

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
    gtk-font-name = "${uiFontName} ${uiFontSizeStr}"
  '';

  gtk3Extra = {
    gtk-theme-name = gtkThemeName;
    gtk-icon-theme-name = iconThemeName;
    gtk-cursor-theme-name = xcurName;
    gtk-font-name = "${uiFontName} ${uiFontSizeStr}";
    gtk-application-prefer-dark-theme = true;
  };

  gtk4Extra = gtk3Extra;

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

  gtk4Css = ''
    /* Minimal GTK4 palette bridge */
    window, .background { background-color: ${bg}; color: ${fg}; }
    headerbar, .titlebar { background-color: ${bgAlt}; color: ${fg}; }
    button { background-color: ${bgAlt}; color: ${fg}; border: 1px solid ${muted}; }
    button:hover { background-color: ${accent}; color: ${bg}; }
    selection, *.selection { background-color: ${accent}; color: ${bg}; }
  '';
in
{
  # Install assets — do NOT read config.home.packages here (avoids recursion).
  home.packages = [
    gtkPkg
    iconPkg
    xcurPkg
  ];

  # Pointer cursor for GTK/Qt (XCursor); Hyprcursor is handled in Hyprland/session.
  home.pointerCursor = {
    name = xcurName;
    package = xcurPkg;
    size = cursSize;
    gtk.enable = true;
  };

  # GTK theming (applies to GTK2/3/4)
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
      size = uiFontSizeInt;   # int, not string
    };

    gtk2.extraConfig = gtk2Extra;
    gtk3.extraConfig = gtk3Extra;
    gtk4.extraConfig = gtk4Extra;
  };

  # Palette-driven CSS drops
  xdg.configFile."gtk-3.0/gtk.css".text = gtk3Css;
  xdg.configFile."gtk-4.0/gtk.css".text = gtk4Css;
}
