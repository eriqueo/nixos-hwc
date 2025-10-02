# domains/system/services/hardware/index.nix
#
# HARDWARE - System services for hardware interaction.
# Manages input devices (keyboard), audio (PipeWire), and hardware monitoring.
#
# USAGE:
#   hwc.system.services.hardware.enable = true;
#   hwc.system.services.hardware.audio.enable = true;
#   hwc.system.services.hardware.keyboard.enable = true;
#   hwc.system.services.hardware.monitoring.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.hardware;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # AUDIO SYSTEM & DESKTOP PORTAL CONFIGURATION
    #=========================================================================
    # This entire block is enabled by the single 'audio.enable' toggle.
    # It includes PipeWire and all its necessary dependencies for a full
    # desktop experience.

    # Real-time kit for low-latency audio processing.
    security.rtkit.enable = lib.mkIf cfg.audio.enable true;

    # The PipeWire audio server itself.
    services.pipewire = lib.mkIf cfg.audio.enable {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true; # Modern session manager for PipeWire
    };

    # UPower service for battery information, often used by audio/power profiles.
    services.upower.enable = lib.mkIf cfg.audio.enable true;

    # XDG portals are essential for sandboxed apps (Flatpaks, etc.) to
    # interact with the system for things like file pickers and screen sharing.
    xdg.portal = lib.mkIf cfg.audio.enable {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    # Keyring service for securely storing secrets for applications.
    services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;

    #=========================================================================
    # UNIVERSAL KEYBOARD MAPPING (keyd)
    #=========================================================================
    # This block is controlled by the 'keyboard.enable' toggle.

    services.keyd = lib.mkIf cfg.keyboard.enable {
      enable = true;
      keyboards.default = {
        ids = [ "*" ]; # Apply to all keyboards
        settings.main = {
          # Universal F-key mapping for consistent behavior.
          f1 = "XF86AudioMute";
          f2 = "XF86AudioLowerVolume";
          f3 = "XF86AudioRaiseVolume";
          f4 = "XF86AudioMicMute";
          f5 = "XF86MonBrightnessDown";
          f6 = "XF86MonBrightnessUp";
          f7 = "XF86TaskPanel";
          f8 = "XF86Bluetooth";
          f9 = "print";
          f10 = "XF86LaunchA";
          f11 = "XF86Display";
          f12 = "XF86Launch1";
        };
      };
    };

    # The 'uinput' kernel module is required for keyd to create virtual input devices.
    boot.kernelModules = lib.mkIf cfg.keyboard.enable [ "uinput" ];

    #=========================================================================
    # CO-LOCATED HARDWARE & UTILITY PACKAGES
    #=========================================================================
    # Packages are now bundled with the module that needs them.
    environment.systemPackages = with pkgs;
      # These packages are installed if the 'monitoring.enable' toggle is on.
      (lib.optionals cfg.monitoring.enable [
        pciutils        # lspci
        usbutils        # lsusb
        lm_sensors      # sensors
        smartmontools   # smartctl
        nvme-cli        # nvme
      ])
      # These packages are installed if the 'audio.enable' toggle is on.
      ++ (lib.optionals cfg.audio.enable [
        pavucontrol     # GUI volume mixer for PulseAudio/PipeWire
        seahorse        # GUI for gnome-keyring
      ]);
  };
}
