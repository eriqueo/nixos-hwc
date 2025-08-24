# modules/home/input.nix
# Charter v3 Universal Input Configuration
# Provides consistent keyboard mapping across all machines and input devices
{ config, lib, pkgs, ... }:

with lib;

let 
  cfg = config.hwc.home.input;
in {
  
  ####################################################################
  # CHARTER V3 OPTIONS
  ####################################################################
  options.hwc.home.input = {
    enable = mkEnableOption "universal input device configuration";
    
    keyboard = {
      enable = mkEnableOption "universal keyboard mapping";
      universalFunctionKeys = mkEnableOption "standardize F-keys across all keyboards";
    };
    
    # Future extensibility
    mouse = {
      enable = mkEnableOption "universal mouse configuration";
    };
    
    touchpad = {
      enable = mkEnableOption "universal touchpad configuration";
    };
  };

  ####################################################################
  # CHARTER V3 IMPLEMENTATION
  ####################################################################
  config = mkIf cfg.enable {
    
    ####################################################################
    # UNIVERSAL KEYBOARD MAPPING
    ####################################################################
    services.keyd = mkIf cfg.keyboard.enable {
      enable = true;

      keyboards.default = mkIf cfg.keyboard.universalFunctionKeys {
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

    ####################################################################
    # FUTURE INPUT DEVICE CONFIGURATIONS
    ####################################################################
    
    # Mouse configuration placeholder
    # services.libinput.mouse = mkIf cfg.mouse.enable {
    #   # Universal mouse settings
    # };
    
    # Touchpad configuration placeholder  
    # services.libinput.touchpad = mkIf cfg.touchpad.enable {
    #   # Universal touchpad settings
    # };
  };
}