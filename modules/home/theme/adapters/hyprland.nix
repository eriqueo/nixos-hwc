# nixos-hwc/modules/home/theme/adapters/hyprland.nix
#
# Theme Adapter: Palette → Hyprland Settings
# Charter v4 compliant - Pure data transformation for Hyprland theming
#
# DEPENDENCIES (Upstream):
#   - modules/home/theme/palettes/deep-nord.nix
#
# USED BY (Downstream):
#   - modules/home/hyprland/parts/theming.nix
#
# USAGE:
#   let palette = import ../palettes/deep-nord.nix {};
#   in import ./hyprland.nix { inherit palette; }
#

{ palette }:
{
  # General settings with theme colors
  general = {
    gaps_in = 6;
    gaps_out = 12;
    border_size = 2;
    "col.active_border" = "rgba(${palette.gruvboxTeal}) rgba(${palette.gruvboxGreen}) 45deg";
    "col.inactive_border" = "rgba(${palette.gruvboxMuted})";
    layout = "dwindle";
    resize_on_border = true;
    allow_tearing = false;
  };
  
  # Decoration with theme-based styling
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
  
  # Animation settings
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
  
  # Dwindle layout settings  
  dwindle = {
    pseudotile = true;
    preserve_split = true;
    smart_split = false;
    smart_resizing = true;
  };
  
  # Miscellaneous settings
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
}