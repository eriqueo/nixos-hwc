# nixos-hwc/modules/home/theme/adapters/gtk.nix
#
# GTK Theme Adapter: Deep Nord Palette → GTK Configuration
# Charter v6 compliant - Transforms palette tokens into GTK theming
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#
# USED BY (Downstream):
#   - modules/home/apps/thunar.nix
#   - Any Home Manager module needing GTK theming
#
# USAGE:
#   let gtkTheme = import ./theme/adapters/gtk.nix { inherit pkgs; };
#   in {
#     gtk = gtkTheme.config;
#   }

{ pkgs, ... }:

let
  palette = import ../palettes/deep-nord.nix {};
in
{
  config = {
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
    
    gtk2.extraConfig = ''
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
    
    gtk3.extraConfig = {
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
    
    gtk4.extraConfig = {
      gtk-theme-name = "Adwaita-dark";
      gtk-icon-theme-name = "Adwaita";
      gtk-font-name = "Inter 11";
      gtk-cursor-theme-name = "Adwaita";
      gtk-cursor-theme-size = 24;
    };
  };
  
  # CSS overrides using palette colors
  gtk3CssOverride = ''
    /* Deep Nord GTK Theme Overrides */
    
    /* Window backgrounds */
    window {
      background-color: ${palette.bg};
      color: ${palette.fg};
    }
    
    /* Sidebar theming for file managers */
    .sidebar {
      background-color: ${palette.bgAlt};
      color: ${palette.fg};
    }
    
    /* Selection colors */
    *:selected {
      background-color: ${palette.accent};
      color: ${palette.bg};
    }
    
    /* Header bars */
    headerbar {
      background-color: ${palette.bgAlt};
      color: ${palette.fg};
    }
    
    /* Entry fields */
    entry {
      background-color: ${palette.bgDark};
      color: ${palette.fg};
      border: 1px solid ${palette.muted};
    }
    
    /* Buttons */
    button {
      background-color: ${palette.bgAlt};
      color: ${palette.fg};
      border: 1px solid ${palette.muted};
    }
    
    button:hover {
      background-color: ${palette.accent};
      color: ${palette.bg};
    }
  '';
}