# domains/home/apps/hyprland/parts/behavior.nix
#
# Keybinds and window rules.
#
# RETURN SHAPE — `{ settings, keybinds }`, not a bare settings attrset.
#   settings : flat Hyprland keys (bind/bindm/windowrule), merged by index.nix
#   keybinds : the same bindings as structured records, for parts/theme.nix to
#              render into the SUPER+? legend card
#
# Each binding is declared ONCE, as a record carrying both its Hyprland
# realization (`act`) and a human description (`desc`). `settings.bind` is
# derived from those records, and so is the legend — so the legend cannot drift
# from the keys it documents. Add a binding here and it appears in both.
#
# WHY THE LEGEND IS NOT READ FROM `hyprctl binds -j`: that API emits malformed
# JSON in Hyprland 0.56.0 (keys and values misaligned — `"keycode": RETURN`,
# `"allow_input_capture": ,`), and it carries no descriptions, so the best it
# could ever print is `exec hyprland-monitor-toggle`.
#
# RECORD SHAPE
#   mods : modifier chord, Hyprland spelling ("SUPER SHIFT", "" for bare keys)
#   key  : keysym, Hyprland spelling ("RETURN", "comma", "XF86AudioMute")
#   act  : dispatcher + args, verbatim ("exec,kitty", "killactive")
#   desc : what it does, in plain words — this is the legend text
#   show : display override for the key (default: prettified `key`)
#   kind : "bind" (default) | "bindm" (mouse)
#   hide : omit from the legend, still bound (for duplicate-keysym aliases)
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
  gsrEnabled = config.hwc.home.apps.gpu-screen-recorder.enable or false;

  # Directional and per-workspace families are mechanical — generate them, so a
  # missing arrow or workspace variant is impossible.
  dirs = [
    {k = "h"; arrow = "left";  d = "l"; label = "left";}
    {k = "l"; arrow = "right"; d = "r"; label = "right";}
    {k = "k"; arrow = "up";    d = "u"; label = "up";}
    {k = "j"; arrow = "down";  d = "d"; label = "down";}
  ];

  focusBinds = lib.concatMap (x: [
    {mods = mod; key = x.k;     act = "movefocus,${x.d}"; desc = "Focus window ${x.label}";}
    {mods = mod; key = x.arrow; act = "movefocus,${x.d}"; desc = "Focus window ${x.label} (arrow)";}
  ]) dirs;

  moveBinds = lib.concatMap (x: [
    {mods = "${mod} ALT"; key = x.k;     act = "exec,hyprland-smart-move ${x.d}"; desc = "Move window ${x.label} (crosses monitors at edge)";}
    {mods = "${mod} ALT"; key = x.arrow; act = "exec,hyprland-smart-move ${x.d}"; desc = "Move window ${x.label} (arrow)";}
  ]) dirs;

  # Pixels per resize step in the `resize` submap (see the submap group below).
  resizeStep = "40";

  wsSlots = [1 2 3 4 5 6 7 8];
  sendToWs = map (n: {
    mods = "${mod} CTRL"; key = toString n;
    act = "exec,hyprsome move ${toString n}";
    desc = "Send window to workspace ${toString n}";
  }) wsSlots;
  switchToWs = map (n: {
    mods = "${mod} CTRL ALT"; key = toString n;
    act = "exec,hwc-workspace-switch ${toString n}";
    desc = "Go to workspace ${toString n}";
  }) wsSlots;

  #==========================================================================
  # THE BINDINGS. Group order here is the order in the legend.
  #==========================================================================
  keybinds = [
    {
      name = "Launch";
      binds =
        [
          {mods = mod;            key = "RETURN"; act = "exec,kitty";                   desc = "Terminal (kitty)";}
          {mods = mod;            key = "SPACE";  act = "exec,wofi --show drun";        desc = "App launcher (wofi)";}
          {mods = mod;            key = "B";      act = "exec,gpu-launch chromium-hwc"; desc = "Chromium";}
          {mods = "${mod} SHIFT"; key = "B";      act = "exec,gpu-launch firefox-hwc";  desc = "Firefox";}
          {mods = mod;            key = "N";      act = "exec,kitty -e nvim";           desc = "Editor (nvim)";}
          {mods = mod;            key = "Y";      act = "exec,kitty -e yazi";           desc = "File manager (yazi)";}
          {mods = mod;            key = "E";      act = "exec,kitty -e ssh -t server aerc"; desc = "Mail (aerc on hwc-server)";}
          {mods = mod;            key = "O";      act = "exec,gpu-launch obsidian";     desc = "Obsidian";}
          {mods = mod;            key = "M";      act = "exec,kitty -e btop";           desc = "Process monitor (btop)";}
          {mods = mod;            key = "C";      act = "exec,kitty -e fend";           desc = "Calculator (fend)";}
          {mods = mod;            key = "A";      act = "exec,proton-authenticator-toggle"; desc = "Proton Authenticator";}
          # `kitty -e` execs its arg directly, so this MUST be a binary on PATH —
          # a zsh alias named wb-reload would be invisible here. wb-reload kills
          # the named session then re-creates it, so every SUPER+W picks up the
          # latest layout instead of reattaching a stale session.
          {mods = mod;            key = "W";      act = "exec,kitty -e wb-reload";      desc = "Workbench (fresh zellij session)";}
          {mods = mod;            key = "V";      act = "exec,cliphist list | wofi --dmenu | cliphist decode | wl-copy"; desc = "Clipboard history";}
          {mods = "${mod} SHIFT"; key = "I";      act = "exec,refinery-intake";         desc = "Refinery intake (capture an idea)";}
        ]
        ++ lib.optionals toduiEnabled [
          {mods = mod; key = "T"; act = "exec,kitty -e todui"; desc = "Tasks (todui)";}
        ]
        ++ lib.optionals dtBindEnabled [
          {mods = mod; key = "D"; act = "exec,kitty --class dt-tui -e dt tui"; desc = "dt TUI";}
        ]
        ++ lib.optionals (dtBindEnabled && dtToggleBind != null) [
          # dtToggleBind arrives pre-joined as "MODS,KEY" from the dt module.
          {
            mods = lib.head (lib.splitString "," dtToggleBind);
            key = lib.concatStringsSep "," (lib.tail (lib.splitString "," dtToggleBind));
            act = "exec,dt toggle";
            desc = "dt toggle";
          }
        ];
    }

    {
      name = "Window";
      binds =
        focusBinds
        ++ moveBinds
        ++ [
          {mods = mod;            key = "F"; act = "fullscreen";                desc = "Fullscreen";}
          {mods = mod;            key = "Q"; act = "killactive";                desc = "Close window";}
          {mods = mod;            key = "S"; act = "pseudo";                    desc = "Pseudo-tile";}
          {mods = mod;            key = "P"; act = "pin";                       desc = "Pin window (on top, all workspaces)";}
          {mods = mod;            key = "R"; act = "submap,resize";             desc = "Resize mode (see below)";}
          {mods = "${mod} CTRL";  key = "h"; act = "layoutmsg,orientationleft"; desc = "Layout: split left";}
          {mods = "${mod} CTRL";  key = "v"; act = "layoutmsg,orientationtop";  desc = "Layout: split top";}
          {mods = mod; key = "mouse:272"; act = "movewindow";   kind = "bindm"; show = "Drag";   desc = "Move floating window (hold + drag)";}
          {mods = mod; key = "mouse:273"; act = "resizewindow"; kind = "bindm"; show = "R-Drag"; desc = "Resize floating window (hold + drag)";}
        ];
    }

    {
      name = "Workspace";
      binds =
        [{mods = mod; key = "TAB"; act = "exec,hyprland-workspace-overview"; desc = "Workspace overview (searchable)";}]
        ++ switchToWs
        ++ sendToWs
        ++ [
          {mods = "${mod} CTRL ALT"; key = "right"; act = "workspace,e+1"; desc = "Next workspace";}
          {mods = "${mod} CTRL ALT"; key = "left";  act = "workspace,e-1"; desc = "Previous workspace";}
          {mods = "${mod} CTRL ALT"; key = "k";     act = "workspace,e+1"; desc = "Next workspace";}
          {mods = "${mod} CTRL ALT"; key = "l";     act = "workspace,e+1"; desc = "Next workspace";}
          {mods = "${mod} CTRL ALT"; key = "j";     act = "workspace,e-1"; desc = "Previous workspace";}
          {mods = "${mod} CTRL ALT"; key = "h";     act = "workspace,e-1"; desc = "Previous workspace";}
          {mods = "${mod} CTRL ALT"; key = "minus"; act = "exec,waybar-workspace-link-toggle"; desc = "Toggle workspace link mode (monitors move together)";}
        ];
    }

    {
      name = "Display & Media";
      binds =
        [
          {mods = "${mod} SHIFT"; key = "M"; act = "exec,hyprland-monitor-toggle"; desc = "Swap external monitor to the other side";}
          {mods = mod;            key = "G"; act = "exec,gpu-toggle";              desc = "Toggle GPU mode (integrated / discrete)";}
          {mods = ""; key = "PRINT"; act = "exec,hyprshot -m region -o $HWC_SCREENSHOTS_DIR/"; desc = "Screenshot a region";}
        ]
        ++ lib.optionals gsrEnabled [
          {mods = "SHIFT"; key = "PRINT"; act = "exec,gsr-toggle"; desc = "Start / stop screen recording";}
        ]
        ++ [
          {mods = ""; key = "XF86AudioRaiseVolume";  act = "exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";   desc = "Volume up";}
          {mods = ""; key = "XF86AudioLowerVolume";  act = "exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";   desc = "Volume down";}
          {mods = ""; key = "XF86AudioMute";         act = "exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";  desc = "Mute output";}
          {mods = ""; key = "XF86AudioMicMute";      act = "exec,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";desc = "Mute microphone";}
          {mods = ""; key = "XF86MonBrightnessUp";   act = "exec,brightnessctl set 10%+"; desc = "Brightness up";}
          {mods = ""; key = "XF86MonBrightnessDown"; act = "exec,brightnessctl set 10%-"; desc = "Brightness down";}
        ];
    }

    {
      name = "Session";
      binds = [
        # SUPER+? twice over on purpose. Hyprland matches on keysym, and with
        # SHIFT held the `/` key reports `question`, not `slash` — which of the
        # two fires depends on the xkb layout. Binding both is free and makes
        # the chord layout-proof; the alias is hidden so the legend shows one
        # row. `comma` is the pre-existing bind, kept for muscle memory.
        {mods = "${mod} SHIFT"; key = "slash";    act = "exec,hyprland-keybinds-viewer"; show = "?"; desc = "This legend";}
        {mods = "${mod} SHIFT"; key = "question"; act = "exec,hyprland-keybinds-viewer"; hide = true; desc = "This legend";}
        {mods = mod;            key = "comma";    act = "exec,hyprland-keybinds-viewer"; desc = "This legend (legacy bind)";}
        {mods = "${mod} SHIFT"; key = "H"; act = "exec,hyprland-system-health-checker"; desc = "System health check";}
        {mods = "${mod} SHIFT"; key = "R"; act = "exec,hyprctl reload";                 desc = "Reload Hyprland config";}
        {mods = "${mod} SHIFT"; key = "Q"; act = "exit";                                desc = "Exit Hyprland";}
      ];
    }

    #------------------------------------------------------------------------
    # SUBMAP GROUP. `submap = "resize"` routes these into
    # wayland.windowManager.hyprland.submaps.resize instead of the global bind
    # list — but they still render in the legend, which is the point: a submap
    # is precisely the mode whose keys you cannot guess.
    #
    # SUPER+R previously entered this submap while NO `submap = resize` block
    # existed anywhere. An empty submap swallows every key and rebinds no exit,
    # so the keyboard was dead until Hyprland restarted. The `escape`/`return`
    # binds below are what make the mode leaveable; do not remove them.
    #
    # `repeat` -> `binde`, which re-fires while the key is held, so resizing is
    # a held key rather than 40 taps. Exits use plain `bind`.
    #------------------------------------------------------------------------
    {
      name = "Resize mode (after SUPER+R)";
      submap = "resize";
      binds = [
        {mods = ""; key = "h"; act = "resizeactive,-${resizeStep} 0"; repeat = true; desc = "Narrower";}
        {mods = ""; key = "l"; act = "resizeactive,${resizeStep} 0";  repeat = true; desc = "Wider";}
        {mods = ""; key = "k"; act = "resizeactive,0 -${resizeStep}"; repeat = true; desc = "Shorter";}
        {mods = ""; key = "j"; act = "resizeactive,0 ${resizeStep}";  repeat = true; desc = "Taller";}
        {mods = ""; key = "left";  act = "resizeactive,-${resizeStep} 0"; repeat = true; hide = true; desc = "Narrower";}
        {mods = ""; key = "right"; act = "resizeactive,${resizeStep} 0";  repeat = true; hide = true; desc = "Wider";}
        {mods = ""; key = "up";    act = "resizeactive,0 -${resizeStep}"; repeat = true; hide = true; desc = "Shorter";}
        {mods = ""; key = "down";  act = "resizeactive,0 ${resizeStep}";  repeat = true; hide = true; desc = "Taller";}
        {mods = ""; key = "escape"; act = "submap,reset"; desc = "Leave resize mode";}
        {mods = ""; key = "return"; act = "submap,reset"; hide = true; desc = "Leave resize mode";}
      ];
    }
  ];

  # Groups carrying `submap` are routed to Hyprland's submaps; the rest are the
  # global bind list. Both come from the one declaration above.
  globalGroups = lib.filter (g: !(g ? submap)) keybinds;
  submapGroups = lib.filter (g: g ? submap) keybinds;

  allBinds = lib.concatMap (g: g.binds) globalGroups;
  ofKind = k: lib.filter (b: (b.kind or "bind") == k) allBinds;
  toHyprland = b: "${b.mods},${b.key},${b.act}";

  # One attr per submap: `binde` for held/repeating keys, `bind` for the rest.
  #
  # `settings` ONLY. Do not add `onDispatch` here: the flake carries two
  # home-manager channels (unstable + release-25.11, see flake.nix `channels`),
  # and the stable module's submap submodule has no such option — setting it
  # passes `homeConfigurations` on an unstable machine and then fails
  # `nix flake check` on a stable one. `settings` exists in both. Omitting it
  # costs nothing: "" is the unstable default, and the explicit escape/return
  # binds below are what leave the mode on either channel.
  mkSubmap = g: {
    name = g.submap;
    value.settings = lib.filterAttrs (_: v: v != []) {
      binde = map toHyprland (lib.filter (b: b.repeat or false) g.binds);
      bind = map toHyprland (lib.filter (b: !(b.repeat or false)) g.binds);
    };
  };
in {
  inherit keybinds;

  submaps = lib.listToAttrs (map mkSubmap submapGroups);

  settings = {
    bind = map toHyprland (ofKind "bind");
    bindm = map toHyprland (ofKind "bindm");

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

      # Keybinds legend (SUPER+?) — float, centered, opaque. Opacity is forced
      # back to 1.0 because the generic kitty rule above would otherwise make
      # the card translucent, and a legend you read through is one you misread.
      "match:class ^(hypr-keybinds)$, float on, center 1, size 1100 900, opacity 1.0"

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
  };
}
