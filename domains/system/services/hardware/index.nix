{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.hardware;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # AUDIO SYSTEM & DESKTOP PORTALS
    #=========================================================================

    security.rtkit.enable = lib.mkIf cfg.audio.enable true;

    services.pipewire = lib.mkIf cfg.audio.enable {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    services.upower.enable = lib.mkIf cfg.audio.enable true;

    # Declarative portals
    xdg.portal = lib.mkIf cfg.audio.enable {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;

    # Order portals after Wayland socket
    systemd.user.services."wayland-ready" = lib.mkIf cfg.audio.enable {
      Unit = {
        Description = "Wait for Wayland socket before starting portals";
        Before = [ "xdg-desktop-portal.service" "xdg-desktop-portal-hyprland.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.bash}/bin/sh -c '
            while [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; do
              sleep 0.2
            done
          '
        '';
        RemainAfterExit = true;
      };
      Install = { WantedBy = [ "default.target" ]; };
    };

    systemd.user.services."xdg-desktop-portal" = lib.mkIf cfg.audio.enable {
      unitConfig = {
        After = [ "wayland-ready.service" ];
        Requires = [ "wayland-ready.service" ];
      };
    };

    systemd.user.services."xdg-desktop-portal-hyprland" = lib.mkIf cfg.audio.enable {
      unitConfig = {
        After = [ "xdg-desktop-portal.service" "wayland-ready.service" ];
        Requires = [ "xdg-desktop-portal.service" "wayland-ready.service" ];
      };
    };

    #=========================================================================
    # UNIVERSAL KEYBOARD MAPPING (keyd)
    #=========================================================================

    services.keyd = lib.mkIf cfg.keyboard.enable {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings.main = {
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

    boot.kernelModules = lib.mkIf cfg.keyboard.enable [ "uinput" ];

    #=========================================================================
    # HARDWARE MONITORING UTILITIES
    #=========================================================================

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
