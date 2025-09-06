# nixos-hwc/modules/home/theme/adapters/hyprland.nix
#
# Hyprland Theme Adapter (v6)
# - Reads active palette from config.hwc.home.theme.colors
# - Exports settings for HM consumers (no file writes)
#
# Usage in HM:
#   let s = config.hwc.home.theme.adapters.hyprland.settings;
#   in { programs.hyprland.settings = lib.mkMerge [ s { /* overrides */ } ]; }

{ config, lib, ... }:

let
  c = config.hwc.home.theme.colors;

  isBareHex = s: builtins.match "^[0-9a-fA-F]{6}([0-9a-fA-F{2}])?$" s != null;
  normalizeHex = s: let
    raw = if lib.hasPrefix "#" s then lib.substring 1 (lib.stringLength s -1) s else s;
    hex = lib.toLower raw;
    len = lib.stringLength hex;
    aarrggbb =
      if len == 8 then
       (lib.substring 6 2 hex) + (lib.substring 0 6 hex)
      else
       hex;
  in "0x" + aarrggbb;

  toHypr = s:
    if lib.hasPrefix "0x" s || lib.hasPrefix "rgb(" s || lib.hasPrefix "rgba(" s then s
    else if lib.hasPrefix "#" s || isBareHex s then normalizeHex s 
    else s;
    
             
  # Pull colors with graceful fallback (palette -> sane defaults)
  tealRaw   = c.accent     or "#7daea3";
  greenRaw  = c.accentAlt  or "#89b482"; 
  mutedRaw  = c.muted      or "#4c566a";
  bgRaw     = c.bg         or "#2e3440";

  # Hypr-friendly color coercion:
  # - "#RRGGBB"  -> "0xRRGGBB"
  # - "0x..."    -> keep
  # - "rgb(...)" / "rgba(...)" -> keep
  # - anything else -> pass through (assume already valid for Hypr)
 # isHexHash = s: lib.hasPrefix "#" s;
 # isHex0x   = s: lib.hasPrefix "0x" s;
 # isRgbLike = s: lib.hasPrefix "rgb(" s || lib.hasPrefix "rgba(" s;

 # toHypr = s:
 #   if isHexHash s then
 #     # strip leading "#" and prefix "0x"
 #     "0x" + (lib.substring 1 (lib.stringLength s - 1) s)
 #   else if isHex0x s || isRgbLike s then
 #     s
 #   else
 #     s;

  teal  = toHypr tealRaw;
  green = toHypr greenRaw;
  muted = toHypr mutedRaw;
  bg    = toHypr bgRaw;

in {
  options.hwc.home.theme.adapters.hyprland.settings = lib.mkOption {
    type = lib.types.attrs;
    description = "Hyprland settings derived from the active palette.";
    default = {
      general = {
        gaps_in = 6;
        gaps_out = 12;
        border_size = 2;
        # Gradient active border at 45deg; teal -> green
        "col.active_border" = "${teal} ${green} 45deg";
        "col.inactive_border" = "${muted}";
        layout = "dwindle";
        resize_on_border = true;
        allow_tearing = false;
      };

      decoration = {
        rounding = 12;
        blur = {
          enabled = true;
          size = 6;
          passes = 3;
          new_optimizations = true;
          ignore_opacity = true;
        };
        shadow = {
          enabled = true;
          range = 8;
          render_power = 2;
          color = "rgba(0, 0, 0, 0.4)";
        };
        dim_inactive = false;
      };

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
        pseudotile = true;
        preserve_split = true;
        smart_split = false;
        smart_resizing = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
        vrr = 1;
        enable_swallow = true;
        swallow_regex = "^(kitty)$";
        animate_manual_resizes = true;
        animate_mouse_windowdragging = true;
        focus_on_activate = true;
        new_window_takes_over_fullscreen = 2;
      };
    };
  };
}
