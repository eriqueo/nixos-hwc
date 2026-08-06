# domains/home/apps/hyprland/parts/theme.nix
#
# Palette -> presentation. Two consumers, one palette:
#   settings : Hyprland's own visual config (borders, blur, shadows, animations)
#   card     : the SUPER+? keybind legend, painted from parts/behavior.nix's
#              `keybinds` records — see `keybindsCard` below
#
# Both are colour translations of hwc.home.theme.colors; they only differ in
# target format (Hyprland `0xAARRGGBB` vs terminal 24-bit ANSI).
{ config, lib, pkgs, keybinds ? [], osConfig ? {}, ...}:
let
  c = (config.hwc.home.theme or {}).colors or {};

  toHypr = colorStr:
    let
      hex = if colorStr == null then "888888" else lib.removePrefix "#" colorStr;
      # Legacy 0x format requires ARGB order, add full opacity alpha if missing
      hexWithAlpha = if builtins.stringLength hex == 6 then "ff${hex}" else hex;
    in "0x${hexWithAlpha}";

  activeBorder1 = toHypr (c.accent or null);
  activeBorder2 = toHypr (c.accentAlt or (c.accent or null));
  inactiveBorder = toHypr (c.muted or null);

  #==========================================================================
  # KEYBIND LEGEND CARD (SUPER+?)
  #
  # The HWC which-key look, same tokens as the aerc card: double border,
  # inverted cream title chip, `->` separator, copper keys, cool-accent group
  # headers, dim footer, no red. Rendered here at build time from behavior.nix's
  # records; parts/session.nix wraps the result in the viewer package.
  #==========================================================================

  # ESC. Nix strings have no \e escape, and a RAW control byte is invalid inside
  # a JSON string, so spell it as \u001b and let fromJSON decode it.
  esc = builtins.fromJSON "\"\\u001b\"";

  hexDigits = {
    "0"=0; "1"=1; "2"=2; "3"=3; "4"=4; "5"=5; "6"=6; "7"=7;
    "8"=8; "9"=9; "a"=10; "b"=11; "c"=12; "d"=13; "e"=14; "f"=15;
  };
  toAnsi = layer: hex:
    let
      n = o: toString (lib.foldl' (a: ch: a * 16 + hexDigits.${lib.toLower ch}) 0
                        (lib.stringToCharacters (builtins.substring o 2 hex)));
    in "${esc}[${layer};2;${n 0};${n 2};${n 4}m";

  fg = toAnsi "38";
  bg = toAnsi "48";
  bold = "${esc}[1m";
  reset = "${esc}[0m";

  cFg0 = c.fg0 or "ebdbb2";
  cFg1 = c.fg1 or "d5c4a1";
  cDim = c.fg3 or "50626f";
  cAcc = c.accent or "d08770";
  cGrp = c.info or "83a598";
  cBg0 = c.bg0 or "1d2021";

  # Hyprland keysym spellings are not reading text. Deliberately ASCII-only:
  # every string that gets MEASURED below must be one byte per column, because
  # lib.stringLength counts bytes (a `←` would be 3 bytes, 1 column, and would
  # silently jag the right border).
  keyNames = {
    RETURN = "Enter"; SPACE = "Space"; TAB = "Tab"; PRINT = "PrtSc";
    comma = ","; slash = "/"; question = "?"; minus = "-";
    left = "Left"; right = "Right"; up = "Up"; down = "Down";
    XF86AudioRaiseVolume = "Vol+"; XF86AudioLowerVolume = "Vol-";
    XF86AudioMute = "Mute"; XF86AudioMicMute = "MicMute";
    XF86MonBrightnessUp = "Bright+"; XF86MonBrightnessDown = "Bright-";
  };
  prettyKey = b: b.show or (keyNames.${b.key} or (lib.toUpper b.key));
  chord = b: lib.concatStringsSep "+"
    ((lib.filter (x: x != "") (lib.splitString " " b.mods)) ++ [(prettyKey b)]);

  shownGroups = map (g: g // {binds = lib.filter (b: !(b.hide or false)) g.binds;}) keybinds;
  shownBinds = lib.concatMap (g: g.binds) shownGroups;
  widest = xs: lib.foldl' (a: s: let n = lib.stringLength s; in if n > a then n else a) 0 xs;

  chordW = widest (map chord shownBinds);
  descW = widest (map (b: b.desc) shownBinds);
  title = " HYPRLAND KEYBINDS ";

  # "  " + chord + "  -> " + desc + "  "
  innerW = lib.max (2 + chordW + 4 + descW + 2) (2 + lib.stringLength title + 2);

  pad = n: lib.concatStrings (lib.genList (_: " ") (lib.max 0 n));

  # `width` is the painted text's width in COLUMNS, passed in rather than
  # measured, so ANSI escape bytes are never counted as content.
  row = width: painted: "${fg cAcc}║${reset}${painted}${pad (innerW - width)}${fg cAcc}║${reset}";
  blank = row 0 "";
  rule = l: r: "${fg cAcc}${l}${lib.concatStrings (lib.genList (_: "═") innerW)}${r}${reset}";

  bindRow = b:
    row (2 + chordW + 4 + lib.stringLength b.desc)
      ("  ${fg cAcc}${bold}${chord b}${pad (chordW - lib.stringLength (chord b))}${reset}"
       + "  ${fg cDim}→${reset} ${fg cFg1}${b.desc}${reset}");

  groupRows = g: let n = lib.toUpper g.name; in
    [blank (row (2 + lib.stringLength n) "  ${fg cGrp}${bold}${n}${reset}")]
    ++ map bindRow g.binds;

  keybindsCard = lib.concatStringsSep "\n" (
    [ (rule "╔" "╗")
      (row (2 + lib.stringLength title) "  ${bg cFg0}${fg cBg0}${bold}${title}${reset}")
      (rule "╠" "╣") ]
    ++ lib.concatMap groupRows shownGroups
    ++ [ blank (rule "╚" "╝")
         "${fg cDim}  /  search      n  next match      q  close${reset}"
         "" ]
  );
in
{
  card = keybindsCard;

  settings = {
  general = {
    gaps_in = 6;
    gaps_out = 12;
    border_size = 2;
    "col.active_border" = "${activeBorder1} ${activeBorder2} 45deg";
    "col.inactive_border" = "${inactiveBorder}";
    layout = "dwindle";
    resize_on_border = true;
    allow_tearing = false;
  };

  decoration = {
    rounding = 12;
    blur = {
      enabled = true;
      size = 4;
      passes = 2;
      new_optimizations = true;
      ignore_opacity = false;
      vibrancy = 0.2;        # Slight color boost (0.0-0.5)
      vibrancy_darkness = 0.1;
    };
    shadow = {
      enabled = true;
      range = 8;
      render_power = 2;
      color = "rgba(0,0,0,0.4)";
    };
    dim_inactive = false;
  };

  layerrule = [
    #"blur on, match:namespace waybar"
    #"blur_popups on, match:namespace waybar"
    #"ignore_alpha 0.1, match:namespace waybar"  # 0.1–0.3 common; prevents sharp edges on rounded corners
  ];
  
  animations = {
    enabled = true;
    bezier = [
      "easeOutQuint,0.23,1,0.32,1"
      "easeInOutCubic,0.65,0.05,0.36,1"
      "linear,0,0,1,1"
    ];
    animation = [
      "windows,1,4,easeOutQuint,slide"
      "windowsOut,1,4,easeInOutCubic,slide"
      "border,1,10,default"
      "fade,1,4,default"
      "workspaces,1,4,easeOutQuint,slide"
    ];
  };

  dwindle = {
    # `pseudotile` was removed from `dwindle` in Hyprland 0.55.x; use the
    # `pseudo` dispatcher to toggle per-window instead.
    preserve_split = true;
    smart_split = false;
    smart_resizing = true;
  };

  misc = {
    disable_hyprland_logo = true;
    disable_splash_rendering = true;
    mouse_move_enables_dpms = true;
    key_press_enables_dpms = true;
    vrr = 0;
    enable_swallow = true;
    swallow_regex = "^(kitty)$";
    animate_manual_resizes = true;
    animate_mouse_windowdragging = true;
    focus_on_activate = true;
    on_focus_under_fullscreen = 2;
  };
  };
}
