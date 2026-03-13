# domains/system/services/hardware/index.nix
#
# HARDWARE - System services for hardware interaction.
# Covers audio (PipeWire), input devices (keyd), monitoring tools,
# and robust portal ordering for sandboxed apps.
#
# Usage:
#   hwc.system.hardware.enable = true;
#   hwc.system.hardware.audio.enable = true;
#   hwc.system.hardware.keyboard.enable = true;
#   hwc.system.hardware.monitoring.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.hardware;
  t = lib.types;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.hardware = {
    # Master toggle
    enable = lib.mkEnableOption "Enable all hardware-related services (audio, input, monitoring)";

    # Sub-modules
    keyboard.enable = lib.mkEnableOption "Enable universal keyboard mapping (keyd)";
    audio.enable    = lib.mkEnableOption "Enable PipeWire audio system and portals";
    bluetooth.enable = lib.mkEnableOption "Enable Bluetooth support";
    monitoring.enable = lib.mkEnableOption "Enable hardware monitoring tools (sensors, smartctl, etc.)";
    mouse.enable = lib.mkEnableOption "Enable mouse-specific tools (Solaar for Logitech, etc.)";

    touchpadFix = {
      enable = lib.mkEnableOption "Reload i2c_hid_acpi at boot (fixes Sensel touchpad scrolling)";
    };

    fanControl = {
      enable = lib.mkEnableOption "Enable ThinkPad fan control via thinkfan";

      levels = lib.mkOption {
        type = t.listOf (t.listOf (t.either t.int t.str));
        # Smooth fan curve with gradual ramp-up to reduce thermal cycling
        default = [
          [ 0             0   55 ]   # Silent zone
          [ 1            53   62 ]   # Gentle ramp
          [ 2            60   68 ]   # Gradual increase
          [ 3            66   74 ]   # Medium cooling
          [ 4            72   80 ]   # Higher cooling (eliminates jump to level 5)
          [ 5            78   88 ]   # Maximum manual control
          [ "level auto" 86 32767 ]  # Emergency firmware handoff
        ];
        description = "Thinkfan level table (value, lower temp C, upper temp C).";
      };
    };

    # Peripherals (printing)
    peripherals = {
      enable = lib.mkEnableOption "CUPS printing support with drivers";

      drivers = lib.mkOption {
        type = t.listOf t.package;
        default = with pkgs; [
          gutenprint
          hplip
          brlaser
          brgenml1lpr
          cnijfilter2
        ];
        description = "Printer driver packages to install";
      };

      avahi = lib.mkEnableOption "Avahi for network printer discovery";

      guiTools = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Install GUI printer management tools";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    #==========================================================================
    # LIBINPUT (touchpad/mouse input handling for Wayland)
    #==========================================================================
    services.libinput = {
      enable = true;
      touchpad = {
        scrollMethod = "twofinger";
        naturalScrolling = true;
        tapping = true;
        disableWhileTyping = true;
      };
    };

    #==========================================================================
    # TOUCHPAD FIX (Sensel i2c touchpad - reload module for scroll support)
    #==========================================================================
    systemd.services.touchpad-fix = lib.mkIf cfg.touchpadFix.enable {
      description = "Reload i2c_hid_acpi to fix Sensel touchpad scrolling";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi
        ${pkgs.coreutils}/bin/sleep 1
        ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
      '';
    };

    #==========================================================================
    # FAN CONTROL (ThinkPad)
    #==========================================================================
    boot.extraModprobeConfig = lib.mkIf cfg.fanControl.enable ''
      options thinkpad_acpi fan_control=1
    '';

    services.thinkfan = lib.mkIf cfg.fanControl.enable {
      enable = true;
      settings = {
        sensors = [
          # Use name-based matching - hwmon device numbers change across boots
          {
            hwmon = "/sys/class/hwmon";
            name = "coretemp";
            indices = [1];
          }
          {
            hwmon = "/sys/class/hwmon";
            name = "thinkpad";
            indices = [1];
          }
        ];
        fans = [
          { tpacpi = "/proc/acpi/ibm/fan"; }
        ];
        levels = cfg.fanControl.levels;
      };
    };

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

      # Portal interface routing for Hyprland sessions
      config = {
        common = {
          default = [ "hyprland" "gtk" ];
        };
        # Hyprland-specific portal routing
        hyprland = {
          default = [ "hyprland" "gtk" ];
          # GTK portal provides Settings (color scheme detection)
          "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
          # GTK portal provides file picker
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
        };
      };

      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    # --- Bombproof ordering for user portal units (no scripts, just metadata)
    #
    # Backend portals (hyprland, gtk) start first, then generic portal discovers them.
    # This prevents the "Timeout was reached" errors on startup.

    # Hyprland portal: starts early, only when Wayland socket exists.
    systemd.user.services.xdg-desktop-portal-hyprland = lib.mkIf cfg.audio.enable {
      unitConfig = {
        PartOf              = [ "graphical-session.target" ];
        After               = [ "graphical-session.target" "dbus.service" ];
        Requires            = [ "dbus.service" ];
        ConditionPathExists = "%t/wayland-1";
      };
    };

    # GTK portal: provides Settings interface (for theme detection) and file picker.
    systemd.user.services.xdg-desktop-portal-gtk = lib.mkIf cfg.audio.enable {
      unitConfig = {
        PartOf  = [ "graphical-session.target" ];
        After   = [ "graphical-session.target" "dbus.service" ];
        Requires= [ "dbus.service" ];
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # Generic portal: starts AFTER backend portals are ready.
    systemd.user.services.xdg-desktop-portal = lib.mkIf cfg.audio.enable {
      unitConfig = {
        PartOf  = [ "graphical-session.target" ];
        After   = [ "graphical-session.target" "dbus.service" "xdg-desktop-portal-hyprland.service" "xdg-desktop-portal-gtk.service" ];
        Requires= [ "dbus.service" ];
      };
    };

    # Optional: keyring commonly used by desktop apps
    # DISABLED: Using pass for credential management instead of gnome-keyring
    # services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;

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
    # BLUETOOTH
    #==========================================================================
    hardware.bluetooth = lib.mkIf cfg.bluetooth.enable {
      enable = true;
      powerOnBoot = true;
      settings.General = {
        DiscoverableTimeout = 0;
        AutoEnable = true;
        Experimental = true;
      };
    };

    services.blueman.enable = lib.mkIf cfg.bluetooth.enable true;

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
      ++ (lib.optionals cfg.mouse.enable [
        pkgs.solaar                  # Logitech device management
      ])
      ++ (lib.optionals cfg.audio.enable [
        pkgs.pavucontrol
        pkgs.seahorse
      ])
      ++ (lib.optionals cfg.peripherals.guiTools [
        pkgs.cups                    # CUPS command line tools
        pkgs.system-config-printer   # GUI printer configuration
      ]);

    services.solaar.enable = lib.mkIf cfg.mouse.enable true;

    #==========================================================================
    # PERIPHERALS (PRINTING)
    #==========================================================================
    services.printing = lib.mkIf cfg.peripherals.enable {
      enable = true;
      drivers = cfg.peripherals.drivers;
    };

    # Network printer discovery
    services.avahi = lib.mkIf (cfg.peripherals.enable && cfg.peripherals.avahi) {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Declare firewall requirements through networking module
    hwc.system.networking.firewall = lib.mkIf cfg.peripherals.enable {
      extraTcpPorts = [ 631 ]; # CUPS web interface
      extraUdpPorts = lib.optionals cfg.peripherals.avahi [ 5353 ]; # mDNS
    };

    assertions = [];
  };

}
