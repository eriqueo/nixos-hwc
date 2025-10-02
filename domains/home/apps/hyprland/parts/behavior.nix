# modules/home/apps/hyprland/parts/behavior.nix
{ lib, pkgs, ... }:
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
    "${mod},B,exec,gpu-launch chromium"
    "${mod},2,exec,gpu-launch chromium"
    "${mod},J,exec,gpu-launch chromium --new-window https://jobtread.com"
    "${mod},3,exec,gpu-launch chromium --new-window https://jobtread.com"
    "${mod},4,exec,gpu-launch electron-mail"
    "${mod},5,exec,gpu-launch obsidian"
    "${mod},6,exec,kitty -e nvim"
    "${mod},M,exec,kitty -e btop"
    "${mod},8,exec,kitty -e btop"
    "${mod},1,exec,kitty -e yazi"
    "${mod},O,exec,gpu-launch obsidian"
    "${mod},E,exec,gpu-launch electron-mail"
    "${mod},N,exec,kitty -e nvim"
    "${mod},T,exec,kitty -e yazi"
    "${mod},G,exec,gpu-toggle"
    "${mod} SHIFT,M,exec,hyprland-monitor-toggle"
    "${mod},TAB,exec,hyprland-workspace-overview"
    "${mod} SHIFT,T,togglefloating"
    "${mod} SHIFT,H,exec,hyprland-system-health-checker"

    ",PRINT,exec,hyprshot -m region -c -o /home/eric/05-media/pictures/screenshots/"

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

  windowrulev2 = [
    "tile,class:^(Chromium-browser)$,title:^.*JobTread.*$"
    "tile,class:^(chromium-.*|Chromium-.*)$"

    # File pickers
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

    # Floating
    "float,class:^(pavucontrol)$"
    "float,class:^(blueman-manager)$"
    "size 800 600,class:^(pavucontrol)$"

    # Opacity
    "opacity 0.95,class:^(kitty)$"
    "opacity 0.90,class:^(yazi)$"

    # PiP
    "float,title:^(Picture-in-Picture)$"
    "pin,title:^(Picture-in-Picture)$"
    "size 640 360,title:^(Picture-in-Picture)$"

    # Misc
    "noshadow,floating:0"
    "idleinhibit focus,class:^(mpv|vlc|youtube)$"
    "idleinhibit fullscreen,class:^(firefox|chromium)$"
    "immediate,class:^(kitty|yazi)$"

    # Gaming
    "fullscreen,class:^(steam_app_).*"
    "immediate,class:^(steam_app_).*"
  ];
}

