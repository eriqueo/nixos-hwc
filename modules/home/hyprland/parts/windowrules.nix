# nixos-hwc/modules/home/hyprland/parts/windowrules.nix
#
# Hyprland Window Rules: All 39 Rules Preserved Exactly  
# Charter v4 compliant - Pure data for window behavior configuration
#
# DEPENDENCIES (Upstream):
#   - None (UI behavior rules)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let wr = import ./parts/windowrules.nix { inherit lib pkgs; };
#   in { windowrulev2 = wr.windowrulev2; }
#

{ lib, pkgs, ... }:
{
  windowrulev2 = [
    # Browser rules
    "tile,class:^(Chromium-browser)$,title:^.*JobTread.*$"
    "workspace 3,class:^(Chromium-browser)$,title:^.*JobTread.*$"
    "tile,class:^(chromium-.*|Chromium-.*)$"
    
    # File picker dialogs - comprehensive patterns
    "float,title:^(Open).*"
    "float,title:^(Save).*"
    "float,title:^(Choose).*"
    "float,title:^(Select).*"
    "float,title:^(Upload).*"
    "float,class:^(file_dialog)$"
    "float,class:^(xdg-desktop-portal-gtk)$"
    "float,class:^(org.gtk.FileChooserDialog)$"
    "move 50 100,title:^(Open).*"
    "move 50 100,title:^(Save).*"
    "move 50 100,title:^(Choose).*"
    "move 50 100,title:^(Select).*"
    "move 50 100,title:^(Upload).*"
    "move 50 100,class:^(xdg-desktop-portal-gtk)$"
    "move 50 100,class:^(org.gtk.FileChooserDialog)$"
    "size 1000 700,title:^(Open).*"
    "size 1000 700,title:^(Save).*"
    "size 1000 700,title:^(Choose).*"
    "size 1000 700,title:^(Select).*"
    "size 1000 700,title:^(Upload).*"
    
    # Floating windows
    "float,class:^(pavucontrol)$"
    "float,class:^(blueman-manager)$"
    "size 800 600,class:^(pavucontrol)$"
    
    # Opacity rules
    "opacity 0.95,class:^(kitty)$"
    "opacity 0.90,class:^(thunar)$"
    
    # Workspace assignments (commented out in original)
    # "workspace 1,class:^(thunar)$"
    # "workspace 2,class:^(chromium-.*|Chromium-.*)$"
    # "workspace 6,class:^(nvim)$"
    # "workspace 7,class:^(kitty)$"
    # "workspace 8,class:^(btop|htop|pavucontrol)$"
    # "workspace 4,class:^(obsidian)$"
    # "workspace 5,class:^(electron-mail)$"
    
    # Picture-in-picture
    "float,title:^(Picture-in-Picture)$"
    "pin,title:^(Picture-in-Picture)$"
    "size 640 360,title:^(Picture-in-Picture)$"
    
    # No shadows for certain windows
    "noshadow,floating:0"
    
    # Inhibit idle for media
    "idleinhibit focus,class:^(mpv|vlc|youtube)$"
    "idleinhibit fullscreen,class:^(firefox|chromium)$"
    
    # Immediate focus for important apps
    "immediate,class:^(kitty|thunar)$"
    
    # Gaming optimizations
    "fullscreen,class:^(steam_app_).*"
    "immediate,class:^(steam_app_).*"
  ];
}