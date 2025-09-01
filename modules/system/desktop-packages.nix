# nixos-hwc/modules/system/desktop-packages.nix
#
# DESKTOP PACKAGES - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.desktop-packages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/system/desktop-packages.nix
#
# USAGE:
#   hwc.system.desktop-packages.enable = true;
#   # TODO: Add specific usage examples

# modules/system/desktop-packages.nix
#
# HWC Desktop System Packages (Charter v3)
# System-level packages required for desktop environment functionality
#
# DEPENDENCIES:
#   Upstream: None (pure system package provider)
#
# USED BY:
#   Downstream: Desktop applications and user environment modules
#   Downstream: profiles/workstation.nix (enables desktop packages)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/system/desktop-packages.nix
#
# USAGE:
#   hwc.system.desktop.enable = true;
#   hwc.system.desktop.waybar = true;
#   hwc.system.desktop.notifications = true;
#
# VALIDATION:
#   - Packages are provided system-wide via environment.systemPackages
#   - No user-specific configuration is done here

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.desktop;
in {
  #============================================================================
  # OPTIONS - Desktop Package Categories
  #============================================================================
  
  options.hwc.system.desktop = {
    enable = lib.mkEnableOption "HWC desktop system packages";
    
    waybar = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable waybar and related status bar packages";
    };
    
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable notification system packages";
    };
    
    audio = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable audio control packages";
    };
    
    systemMonitoring = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable system monitoring tools";
    };
    
    fileManagement = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable file management tools";
    };
    
    networking = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable network management tools";
    };
    
    portals = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable XDG desktop portals";
    };
  };

  #============================================================================
  # IMPLEMENTATION - System Package Provision
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; []
      # Waybar and status bar packages
      ++ lib.optionals cfg.waybar [
        waybar
        wlogout
      ]
      
      # Notification system
      ++ lib.optionals cfg.notifications [
        swaynotificationcenter
        libnotify  # for notify-send
      ]
      
      # Audio control
      ++ lib.optionals cfg.audio [
        pavucontrol
        pulsemixer
      ]
      
      # System monitoring and management
      ++ lib.optionals cfg.systemMonitoring [
        btop
        mission-center
        nvtopPackages.full
        lm_sensors
      ]
      
      # File management
      ++ lib.optionals cfg.fileManagement [
        baobab  # disk usage analyzer
      ]
      
      # Network tools
      ++ lib.optionals cfg.networking [
        networkmanagerapplet
        ethtool
        iw
      ]
      
      # Graphics and mesa tools  
      ++ [
        mesa-demos  # provides glxinfo
      ]
      
      # XDG portals for desktop integration
      ++ lib.optionals cfg.portals [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
  };
}