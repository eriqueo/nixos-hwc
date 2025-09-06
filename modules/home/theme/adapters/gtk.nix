# nixos-hwc/modules/home/theme/adapters/gtk.nix
#
# GTK Theme Adapter (v6):
# - Translates active palette (config.hwc.home.theme.colors) → GTK config + CSS overrides
# - Keeps the same adapter interface you use today:
#     let gtkTheme = import ./theme/adapters/gtk.nix { inherit config lib pkgs; };
#     in { gtk = gtkTheme.config; xdg.configFile."gtk-3.0/gtk.css".text = gtkTheme.gtk3CssOverride; }
#
# NOTE: No direct palette imports; reads from config.hwc.home.theme.colors (set by theme/default.nix)

{ config, lib, pkgs, ... }:

let
  c = config.hwc.home.theme.colors;

  bg     = c.bg     or "#101014";
  bgAlt  = c.bgAlt  or bg;
  bgDark = c.bgDark or bg;
  fg     = c.fg     or "#e5e9f0";
  accent = c.accent or "#88c0d0";
  muted  = c.muted  or "#4c566a";

  gtk2Extra = ''
    gtk-theme-name = "Adwaita-dark"
    gtk-icon-theme-name = "Adwaita"
    gtk-font-name = "Inter 11"
    gtk-cursor-theme-name = "Adwaita"
    gtk-cursor-theme-size = 24
    gtk-toolbar-style = GTK_TOOLBAR_BOTH
    gtk-toolbar-icon-size = GTK_ICON_SIZE_LARGE_TOOLBAR
    gtk-button-images = 1
    gtk-menu-images = 1
    gtk-enable-event-sounds = 1
    gtk-enable-input-feedback-sounds = 1
    gtk-xft-antialias = 1
    gtk-xft-hinting = 1
    gtk-xft-hintstyle = "hintfull"
  '';

  gtk3Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    gtk-cursor-theme-name = "Adwaita";
    gtk-cursor-theme-size = 24;
    gtk-toolbar-style = "GTK_TOOLBAR_BOTH";
    gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
    gtk-button-images = 1;
    gtk-menu-images = 1;
    gtk-enable-event-sounds = 1;
    gtk-enable-input-feedback-sounds = 1;
    gtk-xft-antialias = 1;
    gtk-xft-hinting = 1;
    gtk-xft-hintstyle = "hintfull";
    gtk-recent-files-max-age = 30;
    gtk-recent-files-enabled = true;
  };

  gtk4Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    gtk-cursor-theme-name = "Adwaita";
    gtk-cursor-theme-size = 24;
  };

  gtk3Css = ''
    window {
      background-color: ${bg};
      color: ${fg};
    }

    .sidebar {
      background-color: ${bgAlt};
      color: ${fg};
    }

    *:selected {
      background-color: ${accent};
      color: ${bg};
    }

    headerbar {
      background-color: ${bgAlt};
      color: ${fg};
    }

    entry {
      background-color: ${bgDark};
      color: ${fg};
      border: 1px solid ${muted};
    }

    button {
      background-color: ${bgAlt};
      color: ${fg};
      border: 1px solid ${muted};
    }

    button:hover {
      background-color: ${accent};
      color: ${bg};
    }
  '';
in
{
  config = {
  gtk ={
    enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
    font = {
      name = "Inter";
      size = 11;
    };
    gtk2.extraConfig = gtk2Extra;
    gtk3.extraConfig = gtk3Extra;
    gtk4.extraConfig = gtk4Extra;
  };

  xdg.configFile."gtk-3.0/gtk.css".text = gtk3Css;
  };
}  

