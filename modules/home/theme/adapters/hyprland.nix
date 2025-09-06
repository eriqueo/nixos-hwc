# Hyprland Theme Adapter (v6 - Final Refactor)
# - Reads the active palette from config.hwc.home.theme.colors.
# - Normalizes pure hex codes (e.g., "2e3440") into the "0x" format
#   that Hyprland requires.
# - Exports the final settings via a formal NixOS option.

{ config, lib, ... }:

let
  # 1. Read the active color palette from the central config location.
  c = config.hwc.home.theme.colors;

  # 2. Define a robust helper function to format colors for Hyprland.
  #    It expects pure hex strings from the palette (no '#') and
  #    prepends the "0x" that Hyprland requires.
  toHypr = colorStr:
    if colorStr == null then "0x888888" # Fallback for missing colors
    else "0x" + colorStr;

  # 3. Pull colors from the palette using the helper.
  #    The `or null` pattern ensures that if a color is missing from the
  #    palette, the build won't crash. The helper will use a fallback.
  activeBorder1 = toHypr (c.accent or null);
  activeBorder2 = toHypr (c.accentAlt or null);
  inactiveBorder = toHypr (c.muted or null);

in
{
  # 4. Define the formal option to provide the generated settings.
  options.hwc.home.theme.adapters.hyprland.settings = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true; # Good practice for generated values.
    description = "Hyprland settings derived from the active palette.";
  };

  # 5. Set the value of the option.
  #    This is the final, clean attribute set that will be consumed
  #    by the main hyprland/default.nix module.
  config.hwc.home.theme.adapters.hyprland.settings = {
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
}
