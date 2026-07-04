# domains/system/hardware/index.nix
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
    powerScripts.enable = lib.mkEnableOption "perf-mode/balanced-mode CPU governor toggle scripts";

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

    # Sensel SNSL002D touchpad fix: the i2c_hid_acpi driver fires spurious
    # SW_LID (lid closed) events. libinput sees these and suspends the touchpad,
    # killing two-finger scroll. The bug affects TWO devices:
    #   - /dev/input/event3  "Lid Switch"      — dedicated lid switch device
    #   - /dev/input/event10 "SNSL002D Touchpad" — the touchpad itself also emits SW_LID
    #
    # Five-layer fix:
    # 1. Kernel: button.lid_init_state=open (boot.kernelParams) — suppresses
    #    the spurious initial "lid closed" ACPI report on boot/resume.
    # 2. Udev: LIBINPUT_IGNORE_DEVICE=1 on the dedicated Lid Switch device.
    # 3. libinput quirk: strip EV_SW:SW_LID from the touchpad device itself,
    #    so libinput never sees a lid event from the touchpad regardless of
    #    what triggers it (the root cause of the two-finger scroll breakage).
    # 4. Resume hook: rebind the i2c_hid_acpi driver after every resume so
    #    Hyprland re-opens the device with the quirk applied fresh, clearing
    #    the stale SW_LID=1 state the driver retains from the lid-close event.
    # 5. acpid lid-open hook: same rebind, for lid closes that did NOT suspend
    #    (waybar lid-toggle set to ignore). With no resume, layer 4 never runs
    #    and the stale SW_LID=1 kills two-finger scroll until the next resume.
    #    Redundant-but-harmless alongside layer 4 on a real resume: bind/unbind
    #    failures are swallowed and the device ends up bound either way.
    services.udev.extraRules = lib.mkBefore ''
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="Lid Switch", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      # Rival 3 Wireless: the keyboard HID interface (event7) also has pointer
      # capabilities and emits its own BTN_MIDDLE. Without this, libinput exposes
      # BOTH event6 (mouse) and event7 (keyboard) as pointer devices, causing two
      # conflicting middle-button events per scroll-wheel click. The keyboard
      # interface events are not needed — DPI and extra buttons are firmware-driven.
      KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="SteelSeries SteelSeries Rival 3 Wireless Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';

    environment.etc."libinput/local-overrides.quirks".text = ''
      [SNSL002D Touchpad SW_LID suppression]
      MatchUdevType=touchpad
      MatchName=SNSL002D:00 2C2F:002D Touchpad
      AttrEventCode=-EV_SW
    '';

    # Layer 4: rebind SNSL002D after every resume (see comment above).
    # The driver retains SW_LID=1 across suspend/resume; unbind+bind forces
    # Hyprland to re-open the device, which makes libinput apply the quirk
    # fresh and read the actual lid state (open = 0).
    powerManagement.resumeCommands = ''
      echo "i2c-SNSL002D:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind || true
      sleep 0.3
      echo "i2c-SNSL002D:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind || true
    '';

    # Layer 5: same rebind on lid open via acpid (see comment above). acpid
    # itself is enabled per-machine (machines/laptop/config.nix); a handler
    # without the daemon is inert elsewhere.
    services.acpid.handlers."hwc-sensel-rebind" = {
      event = "button/lid LID open";
      action = ''
        echo "i2c-SNSL002D:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind || true
        sleep 0.3
        echo "i2c-SNSL002D:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind || true
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

    # xdg-document-portal fuse mount lingers across restarts (HM activation
    # restarts the service, the prior fuse mount stays, and the next start
    # fails with "Permission denied" trying to remount on top). Lazy unmount
    # on stop so the path is free when the service restarts.
    systemd.user.services.xdg-document-portal = lib.mkIf cfg.audio.enable {
      serviceConfig.ExecStopPost = lib.mkAfter [
        "-${pkgs.fuse3}/bin/fusermount3 -uz %t/doc"
      ];
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
        ids = [ "*" "-1038:1830" ];  # exclude Rival 3 Wireless keyboard interface (breaks middle button)
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

    # Upstream blueman-applet.service ships with ExecStart= AND nixpkgs's
    # services.blueman writes its own ExecStart= into the generated drop-in.
    # systemd refuses two ExecStart= on a non-oneshot unit. Fix: force the
    # drop-in's ExecStart to be a list whose first element is empty, which
    # NixOS emits as `ExecStart=\nExecStart=<cmd>` — systemd's reset+set
    # pattern. This keeps everything inside the NixOS-generated overrides.conf
    # so we don't collide with the etc-builder symlink at .service.d/.
    systemd.user.services.blueman-applet = lib.mkIf cfg.bluetooth.enable {
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${pkgs.blueman}/bin/blueman-applet"
      ];
    };

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
        pkgs.piper                   # GUI for ratbagd (gaming mouse config)
        pkgs.rivalcfg                # SteelSeries specific CLI config
        pkgs.fwupd                   # Firmware update daemon
      ])
      ++ (lib.optionals cfg.audio.enable [
        pkgs.pavucontrol
        pkgs.seahorse
      ])
      ++ (lib.optionals cfg.peripherals.enable cfg.peripherals.drivers)
      ++ (lib.optionals cfg.peripherals.guiTools [
        pkgs.cups                    # CUPS command line tools
        pkgs.system-config-printer   # GUI printer configuration
      ])
      ++ (lib.optionals cfg.powerScripts.enable [
        # Temporary CPU governor toggles for CPU-intensive tasks
        (pkgs.writeShellScriptBin "perf-mode" ''
          #!/usr/bin/env bash
          # Temporarily switch to maximum CPU performance
          echo "⚡ Switching to Performance Mode..."
          echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
          ${pkgs.libnotify}/bin/notify-send "Performance Mode" "CPU governors set to maximum performance" -i cpu -u normal
          echo "CPU governors set to 'performance'"
          echo "Use 'balanced-mode' to restore power-efficient operation"
        '')
        (pkgs.writeShellScriptBin "balanced-mode" ''
          #!/usr/bin/env bash
          # Restore balanced power-efficient mode
          echo "🔋 Restoring Balanced Mode..."
          echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
          ${pkgs.libnotify}/bin/notify-send "Balanced Mode" "CPU governors restored to power-efficient mode" -i cpu -u normal
          echo "CPU governors set to 'powersave' (dynamic scaling)"
        '')
      ]);

    # Logitech device support (udev rules for Solaar)
    hardware.logitech.wireless.enable = lib.mkIf cfg.mouse.enable true;
    hardware.logitech.wireless.enableGraphical = lib.mkIf cfg.mouse.enable true;

    # Gaming mouse support (SteelSeries, etc.)
    services.ratbagd.enable = lib.mkIf cfg.mouse.enable true;
    services.udev.packages = lib.optionals cfg.mouse.enable [ pkgs.rivalcfg ];
    services.fwupd.enable = lib.mkIf cfg.mouse.enable true;

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
