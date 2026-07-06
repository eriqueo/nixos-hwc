# domains/home/apps/hyprland/parts/behavior.nix
{
  config,
  lib,
  pkgs,
  osConfig ? {},
  ...
}: let
  mod = "SUPER";
  dtCfg =
    config.hwc.home.apps.dt or {
      enable = false;
      hyprland = {
        enable = false;
        toggleBind = null;
      };
    };
  dtBindEnabled = (dtCfg.enable or false) && (dtCfg.hyprland.enable or false);
  dtToggleBind = dtCfg.hyprland.toggleBind or null;
  toduiEnabled = config.hwc.home.apps.todui.enable or false;
  gsrCfg = config.hwc.home.apps.gpu-screen-recorder or {enable = false;};
in {
  # Top-level keys only — Hyprland expects these directly.
  bind =
    [
      ## Launching commands
      "${mod},RETURN,exec,kitty"
      "${mod},SPACE,exec,wofi --show drun"
      "${mod} SHIFT,R,exec,hyprctl reload"
      "${mod} SHIFT,Q,exit"
      "${mod},B,exec,gpu-launch chromium-hwc"
      "${mod} SHIFT,B,exec,gpu-launch firefox-hwc"
      "${mod},M,exec,kitty -e btop"
      "${mod},O,exec,gpu-launch obsidian"
      "${mod},E,exec,kitty -e ssh -t server aerc"
      "${mod},N,exec,kitty -e nvim"
      "${mod},Y,exec,kitty -e yazi"
      # Workbench ops host. `wb-reload` (real binary, apps/workbench/index.nix)
      # kills the named session then re-creates it fresh, so every SUPER+W picks
      # up the latest layout/config instead of reattaching a stale session. NOTE:
      # `kitty -e` execs its arg directly, so this MUST be a binary on PATH — a
      # zsh alias named wb-reload would be invisible here.
      "${mod},W,exec,kitty -e wb-reload"
      "${mod},G,exec,gpu-toggle"
    ]
    ++ lib.optionals toduiEnabled [
      "${mod},T,exec,kitty -e todui"
    ]
    ++ lib.optionals dtBindEnabled [
      "${mod},D,exec,kitty --class dt-tui -e dt tui"
    ]
    ++ lib.optionals (dtBindEnabled && dtToggleBind != null) [
      "${dtToggleBind},exec,dt toggle"
    ]
    ++ [
      "${mod} SHIFT,M,exec,hyprland-monitor-toggle"
      "${mod},TAB,exec,hyprland-workspace-overview"
      "${mod} SHIFT,H,exec,hyprland-system-health-checker"
      "${mod},comma,exec,hyprland-keybinds-viewer"
      "${mod},A,exec,proton-authenticator-toggle"
      "${mod} SHIFT,I,exec,refinery-intake"
      "${mod},C,exec, kitty -e fend"
      "${mod},V,exec,cliphist list | wofi --dmenu | cliphist decode | wl-copy"

      ",PRINT,exec,hyprshot -m region -o $HWC_SCREENSHOTS_DIR/"
    ]
    ++ lib.optionals (gsrCfg.enable or false) [
      # Screen recording toggle (calls) — PRINT=screenshot, SHIFT+PRINT=record
      "SHIFT,PRINT,exec,gsr-toggle"
    ]
    ++ [
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

      # TOGGLE workspace link mode (also clickable via Waybar icon)
      "${mod} CTRL ALT,minus,exec,waybar-workspace-link-toggle"

      # SWITCH focus to WORKSPACE (hwc-workspace-switch handles linked-mode sync)
      "${mod} CTRL ALT,1,exec,hwc-workspace-switch 1"
      "${mod} CTRL ALT,2,exec,hwc-workspace-switch 2"
      "${mod} CTRL ALT,3,exec,hwc-workspace-switch 3"
      "${mod} CTRL ALT,4,exec,hwc-workspace-switch 4"
      "${mod} CTRL ALT,5,exec,hwc-workspace-switch 5"
      "${mod} CTRL ALT,6,exec,hwc-workspace-switch 6"
      "${mod} CTRL ALT,7,exec,hwc-workspace-switch 7"
      "${mod} CTRL ALT,8,exec,hwc-workspace-switch 8"

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

  bindm = [
    # Drag floating windows (e.g. PiP / Meet popups) with the mouse
    "${mod},mouse:272,movewindow"    # SUPER + left-click  drag = move
    "${mod},mouse:273,resizewindow"  # SUPER + right-click drag = resize
  ];

  windowrule = [
    # Chromium tiling
    "match:class ^(Chromium-browser)$, match:title ^.*JobTread.*$, tile on"
    "match:class ^(chromium-.*|Chromium-.*)$, tile on"

    # File pickers - float and center
    "match:title ^(Open).*, float on, center 1, size 1000 700"
    "match:title ^(Save).*, float on, center 1, size 1000 700"
    "match:title ^(Choose).*, float on, center 1, size 1000 700"
    "match:title ^(Select).*, float on, center 1, size 1000 700"
    "match:title ^(Upload).*, float on, center 1, size 1000 700"
    "match:class ^(file_dialog)$, float on, center 1"
    "match:class ^(xdg-desktop-portal-gtk)$, float on, center 1"
    "match:class ^(org.gtk.FileChooserDialog)$, float on, center 1"

    # Floating utilities
    "match:class ^(pavucontrol)$, float on, size 800 600"
    "match:class ^(blueman-manager)$, float on"

    # Opacity
    "match:class ^(kitty)$, opacity 0.95"
    "match:class ^(yazi)$, opacity 0.90"

    # dt TUI — float, fixed size, centered (opened via SUPER+T)
    "match:class ^(dt-tui)$, float on, size 800 500, center 1"

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
