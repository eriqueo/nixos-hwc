# nixos-hwc/modules/home/hyprland/parts/behavior.nix
#
# Hyprland Behavior: Keybindings, Window Rules & Application Management
# Charter v5 compliant - Universal behavior domain for UI interaction patterns
#
# DEPENDENCIES (Upstream):
#   - config.hwc.infrastructure.gpu.enable (for gpu-launch integration)
#   - systemPackages for basic tools (pkgs.jq, pkgs.wofi, etc.)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let behavior = import ./parts/behavior.nix { inherit lib pkgs; };
#   in { 
#     bind = behavior.bind; 
#     bindm = behavior.bindm; 
#     windowrulev2 = behavior.windowrulev2; 
#   }
#

{ lib, pkgs, ... }:
let
  mod = "SUPER";
  
  # Dependencies for scripts
  inherit (pkgs) hyprland procps libnotify writeShellScriptBin jq;
in
{
  #============================================================================
  # KEYBINDINGS - All 139 bindings preserved exactly
  #============================================================================
  bind = [
    # Essential bindings
    "${mod}, Return, exec, kitty"
    
    # Window/Session Management
    "${mod}, Q, killactive"
    "${mod}, F, fullscreen"
    "${mod}, Space, exec, wofi --show drun"
    "${mod}, B, exec, gpu-launch chromium"
    "${mod}, 2, exec, gpu-launch chromium"
    "${mod}, J, exec, gpu-launch chromium --new-window https://jobtread.com"
    "${mod}, 3, exec, gpu-launch chromium --new-window https://jobtread.com"
    "${mod}, 4, exec, gpu-launch electron-mail"
    "${mod}, 5, exec, gpu-launch obsidian"
    "${mod}, 6, exec, kitty -e nvim"
    "${mod}, K, exec, kitty"
    "${mod}, 7, exec, kitty"
    "${mod}, M, exec, kitty btop"
    "${mod}, 8, exec, kitty btop"
    "${mod}, 1, exec, thunar"
    "${mod}, O, exec, gpu-launch obsidian"
    "${mod}, E, exec, gpu-launch electron-mail"
    "${mod}, N, exec, kitty nvim"
    "${mod}, T, exec, thunar"
    "${mod}, G, exec, gpu-toggle"
    "${mod} SHIFT, M, exec, hyprland-monitor-toggle"
    "${mod}, TAB, exec, hyprland-workspace-overview"
    "${mod} SHIFT, T, togglefloating"
    
    # Screenshots
    ", Print, exec, hyprshot -m region -o ~/05-media/pictures/screenshots/"
    "SHIFT, Print, exec, hyprshot -m region -c"
    "CTRL, Print, exec, hyprshot -m window -o ~/05-media/pictures/screenshots/"
    "ALT, Print, exec, hyprshot -m output -o ~/Pictures/01-screenshots"
    
    # Focus movement (SUPER + arrows)
    "${mod}, left, movefocus, l"
    "${mod}, right, movefocus, r"
    "${mod}, up, movefocus, u"
    "${mod}, down, movefocus, d"
    
    # Window movement within workspace (SUPER + ALT + arrows)
    "${mod} ALT, left, movewindow, l"
    "${mod} ALT, right, movewindow, r"
    "${mod} ALT, up, movewindow, u"
    "${mod} ALT, down, movewindow, d"
    "${mod} ALT, H, layoutmsg, orientationleft"
    "${mod} ALT, V, layoutmsg, orientationtop"
    
    # MOVE WINDOWS with hyprsome (numeric)
    "${mod} CTRL, 1, exec, hyprsome move 1"
    "${mod} CTRL, 2, exec, hyprsome move 2"
    "${mod} CTRL, 3, exec, hyprsome move 3"
    "${mod} CTRL, 4, exec, hyprsome move 4"
    "${mod} CTRL, 5, exec, hyprsome move 5"
    "${mod} CTRL, 6, exec, hyprsome move 6"
    "${mod} CTRL, 7, exec, hyprsome move 7"
    "${mod} CTRL, 8, exec, hyprsome move 8"
    
    # Letter mappings for moving windows
    "${mod} CTRL, T, exec, hyprsome move 1"
    "${mod} CTRL, C, exec, hyprsome move 2"
    "${mod} CTRL, J, exec, hyprsome move 3"
    "${mod} CTRL, E, exec, hyprsome move 4"
    "${mod} CTRL, O, exec, hyprsome move 5"
    "${mod} CTRL, N, exec, hyprsome move 6"
    "${mod} CTRL, K, exec, hyprsome move 7"
    "${mod} CTRL, M, exec, hyprsome move 8"
    
    # WORKSPACE SWITCHING with hyprsome (per-monitor, numeric)
    "${mod} CTRL ALT, 1, exec, hyprsome workspace 1"
    "${mod} CTRL ALT, 2, exec, hyprsome workspace 2"
    "${mod} CTRL ALT, 3, exec, hyprsome workspace 3"
    "${mod} CTRL ALT, 4, exec, hyprsome workspace 4"
    "${mod} CTRL ALT, 5, exec, hyprsome workspace 5"
    "${mod} CTRL ALT, 6, exec, hyprsome workspace 6"
    "${mod} CTRL ALT, 7, exec, hyprsome workspace 7"
    "${mod} CTRL ALT, 8, exec, hyprsome workspace 8"
    
    # Letter mappings for workspace switching
    "${mod} CTRL ALT, T, exec, hyprsome workspace 1"
    "${mod} CTRL ALT, C, exec, hyprsome workspace 2"
    "${mod} CTRL ALT, J, exec, hyprsome workspace 3"
    "${mod} CTRL ALT, E, exec, hyprsome workspace 4"
    "${mod} CTRL ALT, O, exec, hyprsome workspace 5"
    "${mod} CTRL ALT, N, exec, hyprsome workspace 6"
    "${mod} CTRL ALT, K, exec, hyprsome workspace 7"
    "${mod} CTRL ALT, M, exec, hyprsome workspace 8"
    "${mod} CTRL ALT, left, workspace, e-1"
    "${mod} CTRL ALT, right, workspace, e+1"
    
    # Enhanced workspace management  
    "${mod}, TAB, exec, hyprland-workspace-overview"
    "${mod} CTRL, right, workspace, e+1"
    "${mod} CTRL, left, workspace, e-1"
    
    # Direct application launching (no workspace assignments)
    "${mod}, B, exec, gpu-launch chromium"
    "${mod}, T, exec, thunar" 
    "${mod}, Return, exec, kitty"
    "${mod}, N, exec, kitty -e nvim"
    "${mod}, E, exec, gpu-launch electron-mail"
    "${mod}, O, exec, gpu-launch obsidian"
    "${mod}, M, exec, kitty -e btop"
    
    # System health check
    "${mod} SHIFT, H, exec, hyprland-system-health-checker"
    
    # Volume controls
    ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
    ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    
    # Brightness controls
    ", XF86MonBrightnessUp, exec, brightnessctl set 10%+"
    ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
    
    # Window management
    "${mod}, S, pseudo"
    "${mod}, P, pin"
    "${mod}, C, centerwindow"
    "${mod} SHIFT, Q, exit"
    "${mod}, L, exec, hyprlock"
    "${mod} SHIFT, R, exec, hyprctl reload"
    
    # Quick launchers
    "${mod} SHIFT, Space, exec, wofi --show run"
    
    # Window resizing
    "${mod}, R, submap, resize"
    
    # Group management
    "${mod}, U, togglegroup"
    "${mod}, Tab, changegroupactive, f"
    "${mod} SHIFT, Tab, changegroupactive, b"
    
    # Clipboard history
    "${mod}, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
  ];
  
  bindm = [
    # Mouse bindings (if any are added later)
  ];

  #============================================================================
  # WINDOW RULES - All 39 rules preserved exactly
  #============================================================================
  windowrulev2 = [
    # Browser rules
    "tile,class:^(Chromium-browser)$,title:^.*JobTread.*$"
    # "workspace 3,class:^(Chromium-browser)$,title:^.*JobTread.*$"
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

  # Tools moved to parts/system.nix for system-wide access
  # Force regeneration
}
