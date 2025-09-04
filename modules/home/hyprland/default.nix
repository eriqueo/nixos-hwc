# nixos-hwc/modules/home/hyprland/default.nix
#
# Home UI: Hyprland Wayland Compositor (Universal Config Domains)
# Charter v5 compliant - Single entrypoint composing universal behavior/hardware/session/appearance domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
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
#   Universal domains: behavior.nix, hardware.nix, session.nix, appearance.nix
#

{ config, lib, pkgs, ... }:
let
  # Import universal config domains
  behavior = import ./parts/behavior.nix { inherit lib pkgs; };
  hardware = import ./parts/hardware.nix { inherit lib pkgs; };
  session = import ./parts/session.nix { inherit lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs; };
  
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
    
    # Universal config domain tools (now managed at system level)
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
      # Hardware domain (monitors, input, workspaces)
      {
        monitor = hardware.monitor;
        workspace = hardware.workspace;
        input = hardware.input;
      }
      
      # Behavior domain (keybindings, window rules) 
      (behavior // { "$mod" = "SUPER"; })
      
      # Session domain (autostart)
      {
        exec-once = session.execOnce;
      }
      
      # Appearance domain (theme settings)
      appearance
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