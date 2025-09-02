# nixos-hwc/modules/home/hyprland/default.nix
#
# Home UI: Hyprland Wayland Compositor (Parts-Based Structure)
# Charter v4 compliant - Single entrypoint composing user-tweakable parts
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#   - modules/infrastructure/hyprland-tools.nix (executable tools)
#   - modules/home/theme/palettes/deep-nord.nix (theme tokens)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#

{ lib, pkgs, ... }:
let
  # Import all parts with consistent interface
  kb = import ./parts/keybindings.nix { inherit lib pkgs; };
  mon = import ./parts/monitors.nix { inherit lib pkgs; };
  wr = import ./parts/windowrules.nix { inherit lib pkgs; };
  inp = import ./parts/input.nix { inherit lib pkgs; };
  auto = import ./parts/autostart.nix { inherit lib pkgs; };
  theme = import ./parts/theming.nix { inherit lib pkgs; };
  
  # Wallpaper path preserved from monolith
  wallpaperPath = "/etc/nixos/hosts/laptop/modules/assets/wallpapers/nord-mountains.jpg";
in
{
  #============================================================================
  # HOME PACKAGES (Hyprland Ecosystem)
  #============================================================================
  home.packages = with pkgs; [
    # Core Hyprland tools (preserved from monolith)
    wofi
    hyprshot
    hypridle
    hyprpaper
    hyprlock
    
    # Clipboard management
    cliphist
    wl-clipboard
    
    # System tools for Hyprland  
    brightnessctl
    networkmanager
    wirelesstools
    
    # Window manager utilities
    hyprsome  # Per-monitor workspace management
  ];
  
  #============================================================================
  # SESSION VARIABLES
  #============================================================================
  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
  };
  
  #============================================================================
  # HYPRLAND CONFIGURATION (Composed from Parts)
  #============================================================================
  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    
    settings = lib.mkMerge [
      # Monitor and workspace layout
      {
        monitor = mon.monitor;
        workspace = mon.workspace;
      }
      
      # Window rules
      {
        windowrulev2 = wr.windowrulev2;
      }
      
      # Input configuration
      {
        input = inp.input;
      }
      
      # Theme settings (colors, decorations, animations)
      theme
      
      # Keybindings and autostart
      {
        "$mod" = "SUPER";
        bind = kb.bind;
        bindm = kb.bindm or [];
        exec-once = auto.execOnce;
      }
    ];
  };
  
  #============================================================================
  # WALLPAPER CONFIGURATION (hyprpaper)
  #============================================================================
  home.file.".config/hypr/hyprpaper.conf".text = ''
    preload = ${wallpaperPath}
    wallpaper = eDP-1,${wallpaperPath}
    wallpaper = DP-1,${wallpaperPath}
    splash = false
  '';
}