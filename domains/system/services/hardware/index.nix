# domains/system/services/hardware/index.nix
#
# HARDWARE - System services for hardware interaction.
# Covers audio (PipeWire), input devices (keyd), monitoring tools,
# and robust portal ordering for sandboxed apps.
#
# Usage:
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

    #==========================================================================
    # AUDIO SYSTEM & DESKTOP PORTALS
    #==========================================================================
    security.rtkit.enable = lib.mkIf cfg.audio.enable true;

    services.pipewire = lib.mkIf cfg.audio.enable {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    services.upower.enable = lib.mkIf cfg.audio.enable true;

    # Portals (system-level) with explicit backend preference
    xdg.portal = lib.mkIf cfg.audio.enable {
      enable = true;

      # Prefer Hyprland backend, then GTK (file picker, etc.)
      config = {
        common.default = [ "hyprland" "gtk" ];
      };

      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    # --- Bombproof ordering for user portal units (no scripts, just metadata)
    #
    # Start generic portal as part of the session and after DBus.
    systemd.user.services.xdg-desktop-portal = lib.mkIf cfg.audio.enable {
      unitConfig = {
        PartOf  = [ "graphical-session.target" ];
        After   = [ "graphical-session.target" "dbus.service" ];
        Requires= [ "dbus.service" ];
      };
    };

    # Hyprland portal: after generic portal and only when the Wayland socket exists.
    # %t expands to XDG_RUNTIME_DIR at runtime; Hyprland creates wayland-1 on your setup.
    systemd.user.services.xdg-desktop-portal-hyprland = lib.mkIf cfg.audio.enable {
      unitConfig = {
        PartOf              = [ "graphical-session.target" ];
        After               = [ "graphical-session.target" "xdg-desktop-portal.service" ];
        Requires            = [ "xdg-desktop-portal.service" ];
        ConditionPathExists = "%t/wayland-1";
      };
    };

    # Optional: keyring commonly used by desktop apps
    services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;

    #==========================================================================
    # UNIVERSAL KEYBOARD MAPPING (keyd)
    #==========================================================================
    services.keyd = lib.mkIf cfg.keyboard.enable {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings.main = {
          f1  = "XF86AudioMute";
          f2  = "XF86AudioLowerVolume";
          f3  = "XF86AudioRaiseVolume";
          f4  = "XF86AudioMicMute";
          f5  = "XF86MonBrightnessDown";
          f6  = "XF86MonBrightnessUp";
          f7  = "XF86TaskPanel";
          f8  = "XF86Bluetooth";
          f9  = "print";
          f10 = "XF86LaunchA";
          f11 = "XF86Display";
          f12 = "XF86Launch1";
        };
      };
    };

    # keyd needs uinput to create a virtual keyboard device
    boot.kernelModules = lib.mkIf cfg.keyboard.enable [ "uinput" ];

    #==========================================================================
    # CO-LOCATED HARDWARE & UTILITY PACKAGES
    #==========================================================================
    environment.systemPackages =
      (lib.optionals cfg.monitoring.enable [
        pkgs.pciutils
        pkgs.usbutils
        pkgs.lm_sensors
        pkgs.smartmontools
        pkgs.nvme-cli
      ])
      ++ (lib.optionals cfg.audio.enable [
        pkgs.pavucontrol
        pkgs.seahorse
      ]);
  };
}
