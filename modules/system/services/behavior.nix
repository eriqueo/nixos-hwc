# nixos-hwc/modules/system/services/behavior.nix
#
# BEHAVIOR - System input behavior and audio configuration
# Combines keyboard input mapping with audio system for unified system behavior control
#
# DEPENDENCIES (Upstream):
#   - None (base system services)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.system.services.behavior.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/system/services/behavior.nix
#
# USAGE:
#   hwc.system.services.behavior.enable = true;
#   hwc.system.services.behavior.keyboard.universalFunctionKeys = true;
#   hwc.system.services.behavior.audio.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.behavior;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================

  options.hwc.system.services.behavior = {
    enable = lib.mkEnableOption "system input behavior and audio configuration";

    # Keyboard behavior configuration
    keyboard = {
      enable = lib.mkEnableOption "universal keyboard mapping";
      universalFunctionKeys = lib.mkEnableOption "standardize F-keys across all keyboards";
    };

    # Future input device extensibility
    mouse = {
      enable = lib.mkEnableOption "universal mouse configuration";
    };

    touchpad = {
      enable = lib.mkEnableOption "universal touchpad configuration";
    };

    # Audio system configuration
    audio = {
      enable = lib.mkEnableOption "PipeWire audio system";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # UNIVERSAL KEYBOARD MAPPING
    #=========================================================================
    
    services.keyd = lib.mkIf cfg.keyboard.enable {
      enable = true;

      keyboards.default = lib.mkIf cfg.keyboard.universalFunctionKeys {
        ids = [ "*" ];  # Apply to all keyboards
        settings.main = {
          # Universal F-key mapping matching Lenovo laptop layout
          # Provides consistent behavior across all keyboards
          f1 = "XF86AudioMute";           # Audio mute (toggle speakers)
          f2 = "XF86AudioLowerVolume";    # Volume down
          f3 = "XF86AudioRaiseVolume";    # Volume up
          f4 = "XF86AudioMicMute";        # Microphone mute (toggle mic)
          f5 = "XF86MonBrightnessDown";   # Screen brightness down
          f6 = "XF86MonBrightnessUp";     # Screen brightness up
          f7 = "XF86TaskPanel";           # Show all workspaces (workspace picker)
          f8 = "XF86Bluetooth";           # Bluetooth manager (was "Mode" key)
          f9 = "print";                   # Print Screen (full screenshot)
          f10 = "XF86LaunchA";            # Area screenshot (lasso-style capture)
          f11 = "XF86Display";            # Switch external monitor position
          f12 = "XF86Launch1";            # Toggle GPU offload mode
        };
      };
    };

    # Enable uinput kernel module for keyd device access
    boot.kernelModules = lib.mkIf cfg.keyboard.enable [ "uinput" ];

    #=========================================================================
    # AUDIO SYSTEM CONFIGURATION
    #=========================================================================

    # Real-time kit for audio processing
    security.rtkit.enable = lib.mkIf cfg.audio.enable true;
    
    # PipeWire audio server
    services.pipewire = lib.mkIf cfg.audio.enable {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    
    # UPower for battery information (used by wireplumber)
    services.upower.enable = lib.mkIf cfg.audio.enable true;
    
    # XDG portal configuration (for desktop integration)
    xdg.portal = lib.mkIf cfg.audio.enable {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk xdg-desktop-portal-hyprland ];
      config.common.default = "*";  # Keep < 1.17 behavior for compatibility
    };

    # Keyring integration for secure app vaults (ProtonMail Bridge, etc.)
    services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;
    programs.seahorse.enable = lib.mkIf cfg.audio.enable true;

    #=========================================================================
    # FUTURE INPUT DEVICE CONFIGURATIONS
    #=========================================================================
    
    # Mouse configuration placeholder
    # services.libinput.mouse = lib.mkIf cfg.mouse.enable {
    #   # Universal mouse settings
    # };
    
    # Touchpad configuration placeholder  
    # services.libinput.touchpad = lib.mkIf cfg.touchpad.enable {
    #   # Universal touchpad settings
    # };
  };
}