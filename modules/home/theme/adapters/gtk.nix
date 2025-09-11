# GTK Theme Adapter (v7 - Modern & Stable)
# Translates the active palette into GTK settings with reliable, modern defaults.
{ config, lib, pkgs, ... }:
let
  # Read the active color palette
  c = config.hwc.home.theme.colors;
  
  # Helper to format colors for GTK CSS
  toGtk = colorStr:
    if colorStr == null then "#888888"
    else "#" + (lib.removePrefix "#" colorStr);
  
  # Extract colors from palette
  bg     = toGtk (c.bg or null);
  bgAlt  = toGtk (c.bgAlt or null);
  bgDark = toGtk (c.bgDark or null);
  fg     = toGtk (c.fg or null);
  accent = toGtk (c.accent or null);
  muted  = toGtk (c.muted or null);
  
  # Modern GTK configurations
  gtk2Extra = ''
    gtk-theme-name = "Adwaita-dark"
    gtk-icon-theme-name = "Papirus-Dark"
    gtk-cursor-theme-name = "Adwaita"
    gtk-font-name = "Inter 11"
  '';
  
  gtk3Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Papirus-Dark";
    gtk-cursor-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    gtk-application-prefer-dark-theme = true;
  };
  
  gtk4Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Papirus-Dark";
    gtk-cursor-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    gtk-application-prefer-dark-theme = true;
  };
  
  # Custom GTK3 CSS for palette colors
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
  options.hwc.home.theme.adapters.gtk = {
    settings = lib.mkOption {
      type = lib.types.attrs;
      description = "GTK settings derived from active palette";
      default = {
        gtk = {
          enable = true;
          theme = { 
            name = "Adwaita-dark"; 
            package = pkgs.gnome-themes-extra; 
          };
          iconTheme = { 
            name = "Papirus-Dark"; 
            package = pkgs.papirus-icon-theme; 
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
    };
    gtk3Css = lib.mkOption {
      type = lib.types.str;
      description = "GTK3 CSS derived from active palette";
      default = gtk3Css;
    };
  };
}
