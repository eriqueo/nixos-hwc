# System-lane configuration for RetroArch
# Imported by system profiles, not by Home Manager
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.retroarch;
in
{
  config = lib.mkIf cfg.enable {
    # System packages for controller support
    environment.systemPackages = with pkgs; [
      # Controller utilities
      evtest
      jstest-gtk
      antimicrox  # Keyboard/mouse mapping for controllers
    ];

    # Udev rules for controller access
    services.udev.extraRules = ''
      # Nintendo Switch Pro Controller
      KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0666"

      # Xbox controllers
      KERNEL=="hidraw*", ATTRS{idVendor}=="045e", MODE="0666"

      # PlayStation controllers
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0666"

      # 8BitDo controllers
      KERNEL=="hidraw*", ATTRS{idVendor}=="2dc8", MODE="0666"

      # Generic USB gamepads
      SUBSYSTEM=="input", GROUP="input", MODE="0660"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0079", MODE="0666"
    '';

    # Add user to input group for controller access
    users.users.eric.extraGroups = [ "input" ];

    # Enable joystick support
    hardware.enableRedistributableFirmware = true;
  };
}
