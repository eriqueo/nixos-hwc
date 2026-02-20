# modules/home/apps/hyprland/parts/behavior.nix
{ lib, pkgs, osConfig ? {}, ... }:
let
  mod = "SUPER";
in
{
  # Top-level keys only — Hyprland expects these directly.
  bind = [
    "${mod},RETURN,exec,kitty"
    "${mod},SPACE,exec,wofi --show drun"
    "${mod},L,exec,hyprlock"
    "${mod} SHIFT,R,exec,hyprctl reload"
    "${mod} SHIFT,Q,exit"
    "${mod},B,exec,gpu-launch librewolf"
    "${mod},2,exec,gpu-launch librewofl"
    "${mod},J,exec,gpu-launch chromium --new-window https://jobtread.com"
    "${mod},3,exec,gpu-launch chromium --new-window https://jobtread.com"
    "${mod},4,exec,kitty -e aerc"
    "${mod},5,exec,gpu-launch obsidian"
    "${mod},6,exec,kitty -e nvim"
    "${mod},M,exec,kitty -e btop"
    "${mod},8,exec,kitty -e btop"
    "${mod},1,exec,kitty -e yazi"
    "${mod},O,exec,gpu-launch obsidian"
    "${mod},E,exec,kitty -e aerc"
    "${mod},N,exec,kitty -e nvim"
    "${mod},T,exec,kitty -e yazi"
    "${mod},G,exec,gpu-toggle"
    "${mod} SHIFT,M,exec,hyprland-monitor-toggle"
    "${mod},TAB,exec,hyprland-workspace-overview"
    "${mod} SHIFT,T,togglefloating"
    "${mod} SHIFT,H,exec,hyprland-system-health-checker"
    "${mod},A,exec,proton-authenticator-toggle"

    ",PRINT,exec,hyprshot -m region -o $HWC_SCREENSHOTS_DIR/"

    "${mod},left,movefocus,l"
    "${mod},right,movefocus,r"
    "${mod},up,movefocus,u"
    "${mod},down,movefocus,d"

    "${mod} ALT,left,movewindow,l"
    "${mod} ALT,right,movewindow,r"
    "${mod} ALT,up,movewindow,u"
    "${mod} ALT,down,movewindow,d"
    "${mod} ALT,H,layoutmsg,orientationleft"
    "${mod} ALT,V,layoutmsg,orientationtop"

    "${mod} CTRL,1,exec,hyprsome move 1"
    "${mod} CTRL,2,exec,hyprsome move 2"
    "${mod} CTRL,3,exec,hyprsome move 3"
    "${mod} CTRL,4,exec,hyprsome move 4"
    "${mod} CTRL,5,exec,hyprsome move 5"
    "${mod} CTRL,6,exec,hyprsome move 6"
    "${mod} CTRL,7,exec,hyprsome move 7"
    "${mod} CTRL,8,exec,hyprsome move 8"

    "${mod} CTRL,T,exec,hyprsome move 1"
    "${mod} CTRL,C,exec,hyprsome move 2"
    "${mod} CTRL,J,exec,hyprsome move 3"
    "${mod} CTRL,E,exec,hyprsome move 4"
    "${mod} CTRL,O,exec,hyprsome move 5"
    "${mod} CTRL,N,exec,hyprsome move 6"
    "${mod} CTRL,K,exec,hyprsome move 7"
    "${mod} CTRL,M,exec,hyprsome move 8"

    "${mod} CTRL ALT,1,exec,hyprsome workspace 1"
    "${mod} CTRL ALT,2,exec,hyprsome workspace 2"
    "${mod} CTRL ALT,3,exec,hyprsome workspace 3"
    "${mod} CTRL ALT,4,exec,hyprsome workspace 4"
    "${mod} CTRL ALT,5,exec,hyprsome workspace 5"
    "${mod} CTRL ALT,6,exec,hyprsome workspace 6"
    "${mod} CTRL ALT,7,exec,hyprsome workspace 7"
    "${mod} CTRL ALT,8,exec,hyprsome workspace 8"

    "${mod} CTRL ALT,T,exec,hyprsome workspace 1"
    "${mod} CTRL ALT,C,exec,hyprsome workspace 2"
    "${mod} CTRL ALT,J,exec,hyprsome workspace 3"
    "${mod} CTRL ALT,E,exec,hyprsome workspace 4"
    "${mod} CTRL ALT,O,exec,hyprsome workspace 5"
    "${mod} CTRL ALT,N,exec,hyprsome workspace 6"
    "${mod} CTRL ALT,K,exec,hyprsome workspace 7"
    "${mod} CTRL ALT,M,exec,hyprsome workspace 8"

    "${mod} CTRL ALT,right,workspace,e+1"
    "${mod} CTRL ALT,left,workspace,e-1"

    ",XF86AudioRaiseVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
    ",XF86AudioLowerVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ",XF86AudioMute,exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ",XF86AudioMicMute,exec,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"

    ",XF86MonBrightnessUp,exec,brightnessctl set 10%+"
    ",XF86MonBrightnessDown,exec,brightnessctl set 10%-"

    "${mod},S,pseudo"
    "${mod},P,pin"
    "${mod},C,centerwindow"
    "${mod},R,submap,resize"
    "${mod},F,fullscreen"
    "${mod},Q,killactive"
  ];

  bindm = [ ];

  windowrule = [
    # Chromium tiling
    "match:class ^(Chromium-browser)$, match:title ^.*JobTread.*$, tile on"
    "match:class ^(chromium-.*|Chromium-.*)$, tile on"

    # File pickers - float and position
    "match:title ^(Open).*, float on, move 50 100, size 1000 700"
    "match:title ^(Save).*, float on, move 50 100, size 1000 700"
    "match:title ^(Choose).*, float on, move 50 100, size 1000 700"
    "match:title ^(Select).*, float on, move 50 100, size 1000 700"
    "match:title ^(Upload).*, float on, move 50 100, size 1000 700"
    "match:class ^(file_dialog)$, float on"
    "match:class ^(xdg-desktop-portal-gtk)$, float on, move 50 100"
    "match:class ^(org.gtk.FileChooserDialog)$, float on, move 50 100"

    # Floating utilities
    "match:class ^(pavucontrol)$, float on, size 800 600"
    "match:class ^(blueman-manager)$, float on"

    # Opacity
    "match:class ^(kitty)$, opacity 0.95"
    "match:class ^(yazi)$, opacity 0.90"

    # Proton Authenticator - tile on workspace 8, suppress fullscreen
    "match:class ^(Proton-authenticator)$, tile on, workspace 8 silent, size 400 600, suppress_event fullscreen"

    # Proton Pass - tile on workspace 8
    "match:class ^(Proton Pass)$, tile on, workspace 8 silent"

    # PiP
    "match:title ^(Picture-in-Picture)$, float on, pin on, size 640 360"

    # Misc
    "match:float 0, no_shadow on"
    "match:class ^(mpv|vlc|youtube)$, idle_inhibit focus"
    "match:class ^(firefox|chromium)$, idle_inhibit fullscreen"
    "match:class ^(kitty|yazi)$, immediate on"

    # Gaming
    "match:class ^(steam_app_).*, fullscreen on, immediate on"
  ];
}
