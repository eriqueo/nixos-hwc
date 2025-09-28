# nixos-hwc/profiles/sys.nix
#
# System Overlay Profile (Workstation-specific toggles, no base imports)
# This file assumes profiles/base.nix is already imported by the machine.
# It DOES NOT import modules/system/index.nix to avoid duplication.
#
# Salvaged from the former workstation.nix:
#  - GPU type, behavior/audio/keyboard toggles
#  - Thermal, polkit module toggle (kept off here to avoid dup; base sets security.polkit)
#  - Login manager configuration (Hyprland, autologin for eric)
#  - Hardware peripherals/permissions/storage backup toggles
#  - Infrastructure session services toggle
#  - User backup service toggles
#  - Server backup import (unique import retained)

{ lib, pkgs, ... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  # Keep ONLY imports not already included by base.nix
  imports = [
    ../domains/server/backup/user-backup.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  # ---- Workstation hardware/infrastructure overlays ------------------------

  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia";  # change to "intel" / "amd" per host as needed
  };

  # Input/audio behavior layer
  hwc.system.services.behavior = {
    enable = true;
    keyboard = {
      enable = true;
      universalFunctionKeys = true;
    };
    audio.enable = true;
  };

  # Thermal/power tuning
  hwc.system.core.thermal = {
    enable = true;
    powerManagement.enable = true;
    disableIncompatibleServices = true;
  };

  # Polkit: base.nix already sets security.polkit.enable = true
  # If you use a module-level toggle (hwc.system.core.polkit.enable), uncomment:
  # hwc.system.core.polkit.enable = true;

  # Login manager (greeter + session; sudo/linger already in base)
  hwc.system.services.session.loginManager = {
    enable = true;
    defaultUser = "eric";
    defaultCommand = "Hyprland";
    autoLogin = true;
    # Optional greeter UX
    showTime = true;
    greeterExtraArgs = [ "--remember" "--remember-user-session" ];
  };

  # Hardware conveniences (USB, groups/permissions, external backup storage)
  hwc.infrastructure = {
    hardware = {
      peripherals = {
        enable = true;
        avahi = true;
      };
      permissions = {
        enable = true;
        groups = {
          media = true;
          development = true;
          virtualization = true;
          hardware = true;
        };
      };
      storage = {
        backup = {
          enable = true;
          externalDrive.autoMount = true;
        };
      };
    };

    # Session services aggregator (if your infra module expects this)
    session.services.enable = true;
  };

  # System backup packages (if your modules/system/basePackages exposes this)
  hwc.system.backupPackages = {
    enable = true;
    protonDrive = {
      enable = true;
      useSecret = false;  # keep as in workstation.nix
    };
    monitoring.enable = true;
  };

  # User backup service orchestration (retained from workstation.nix)
  hwc.services.backup.user = {
    enable = true;
    externalDrive.enable = true;
    protonDrive = {
      enable = true;
      useSecret = false;
    };
    schedule = {
      enable = true;
      frequency = "daily";
    };
    notifications.enable = true;
  };
}
