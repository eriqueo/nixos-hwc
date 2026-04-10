# modules/home/apps/hyprland/parts/behavior.nix
{ lib, pkgs, osConfig ? {}, ... }:
let
  mod = "SUPER";
in
{
  # Top-level keys only — Hyprland expects these directly.
  bind = [
    ## Launching commands
    "${mod},RETURN,exec,kitty"
    "${mod},SPACE,exec,wofi --show drun"
    "${mod} SHIFT,R,exec,hyprctl reload"
    "${mod} SHIFT,Q,exit"
    "${mod},B,exec,gpu-launch librewolf"
    "${mod},M,exec,kitty -e btop"
    "${mod},O,exec,gpu-launch obsidian"
    "${mod},E,exec,kitty -e ssh -t hwc aerc"
    "${mod},N,exec,kitty -e nvim"
    "${mod},Y,exec,kitty -e yazi"
    "${mod},G,exec,gpu-toggle"
    "${mod} SHIFT,M,exec,hyprland-monitor-toggle"
    "${mod},TAB,exec,hyprland-workspace-overview"
    "${mod} SHIFT,T,togglefloating"
    "${mod} SHIFT,H,exec,hyprland-system-health-checker"
    "${mod},comma,exec,hyprland-keybinds-viewer"
    "${mod},A,exec,proton-authenticator-toggle"
    "${mod},C,exec, kitty -e fend"

",PRINT,exec,hyprshot -m region -o $HWC_SCREENSHOTS_DIR/"

# move FOCUS in workspace (h=left, j=down, k=up, l=right)
    "${mod},h,movefocus,l"
    "${mod},l,movefocus,r"
    "${mod},k,movefocus,u"
    "${mod},j,movefocus,d"
    "${mod},left,movefocus,l"
    "${mod},right,movefocus,r"
    "${mod},up,movefocus,u"
    "${mod},down,movefocus,d"
# move WINDOW - smart move (within workspace, crosses monitors at edges)
    "${mod} ALT,h,exec,hyprland-smart-move l"
    "${mod} ALT,l,exec,hyprland-smart-move r"
    "${mod} ALT,k,exec,hyprland-smart-move u"
    "${mod} ALT,j,exec,hyprland-smart-move d"
    "${mod} ALT,left,exec,hyprland-smart-move l"
    "${mod} ALT,right,exec,hyprland-smart-move r"
    "${mod} ALT,up,exec,hyprland-smart-move u"
    "${mod} ALT,down,exec,hyprland-smart-move d"
# layout orientation
    "${mod} CTRL,h,layoutmsg,orientationleft"
    "${mod} CTRL,v,layoutmsg,orientationtop"
# SEND window TO workspace 
    "${mod} CTRL,1,exec,hyprsome move 1"
    "${mod} CTRL,2,exec,hyprsome move 2"
    "${mod} CTRL,3,exec,hyprsome move 3"
    "${mod} CTRL,4,exec,hyprsome move 4"
    "${mod} CTRL,5,exec,hyprsome move 5"
    "${mod} CTRL,6,exec,hyprsome move 6"
    "${mod} CTRL,7,exec,hyprsome move 7"
    "${mod} CTRL,8,exec,hyprsome move 8"

# SWITCH focus to WORKSPACE
    "${mod} CTRL ALT,1,exec,hyprsome workspace 1"
    "${mod} CTRL ALT,2,exec,hyprsome workspace 2"
    "${mod} CTRL ALT,3,exec,hyprsome workspace 3"
    "${mod} CTRL ALT,4,exec,hyprsome workspace 4"
    "${mod} CTRL ALT,5,exec,hyprsome workspace 5"
    "${mod} CTRL ALT,6,exec,hyprsome workspace 6"
    "${mod} CTRL ALT,7,exec,hyprsome workspace 7"
    "${mod} CTRL ALT,8,exec,hyprsome workspace 8"


    "${mod} CTRL ALT,right,workspace,e+1"
    "${mod} CTRL ALT,left,workspace,e-1"
    "${mod} CTRL ALT,k,workspace,e+1"
    "${mod} CTRL ALT,l,workspace,e+1"
    "${mod} CTRL ALT,j,workspace,e-1"
    "${mod} CTRL ALT,h,workspace,e-1"

    ",XF86AudioRaiseVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
    ",XF86AudioLowerVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ",XF86AudioMute,exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ",XF86AudioMicMute,exec,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"

    ",XF86MonBrightnessUp,exec,brightnessctl set 10%+"
    ",XF86MonBrightnessDown,exec,brightnessctl set 10%-"

    "${mod},S,pseudo"
    "${mod},P,pin"
    
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

    # DOSBox ECE (eXoWin3x) — inhibit idle during play
    "match:class ^(dosbox)$, idle_inhibit always"

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
