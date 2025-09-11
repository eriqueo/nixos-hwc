# GTK Theme Adapter (v6 - Final Refactor)
# Translates the active palette into GTK settings and a GTK3 CSS override.
# It now correctly handles pure hex codes from the palette.

{ config, lib, pkgs, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # 2. Define a "smart" helper to format colors for GTK CSS.
  #    It ensures the color code is always prefixed with a '#'.
  toGtk = colorStr:
    if colorStr == null then "#888888" # Fallback for missing colors
    else "#" + (lib.removePrefix "#" colorStr);

  # 3. Pull colors from the palette using the helper.
  bg     = toGtk (c.bg or null);
  bgAlt  = toGtk (c.bgAlt or null);
  bgDark = toGtk (c.bgDark or null);
  fg     = toGtk (c.fg or null);
  accent = toGtk (c.accent or null);
  muted  = toGtk (c.muted or null);

  # --- Static GTK2/3/4 configuration (unchanged) ---
  gtk2Extra = ''
    gtk-theme-name = "Adwaita-dark"
    gtk-icon-theme-name = "Adwaita"
    gtk-font-name = "Inter 11"
    # ... etc ...
  '';

  gtk3Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    # ... etc ...
  };

  gtk4Extra = {
    gtk-theme-name = "Adwaita-dark";
    gtk-icon-theme-name = "Adwaita";
    gtk-font-name = "Inter 11";
    # ... etc ...
  };

  # --- Dynamic GTK3 CSS using the formatted colors ---
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
  # 4. Define the formal options to provide this data to the system.
  options.hwc.home.theme.adapters.gtk = {
    settings = lib.mkOption {
      type = lib.types.attrs;
      description = "GTK settings derived from active palette";
      default = {
        gtk = {
          enable = true;
          theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
          iconTheme = { name = "Adwaita"; package = pkgs.adwaita-icon-theme; };
          cursorTheme = { name = "capitaine-cursors"; package = pkgs.capitaine-cursors; size = 24; };
          font = { name = "Inter"; size = 11; };
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
