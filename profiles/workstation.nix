# nixos-hwc/profiles/workstation.nix
#
# WORKSTATION PROFILE - NixOS orchestration only (v6)
# Imports system/infrastructure/services modules. No Home Manager here.

{ lib, ... }:
{
  imports = [
    # System (now auto-imported via base.nix)
    # ../modules/system/ components imported via profiles/base.nix

    # Infrastructure (3-bucket aggregator)
    ../modules/infrastructure/index.nix

    # Services
    ../modules/services/backup/user-backup.nix


  ];

  hwc.system = {
    users = {
      enable = true;
      user = {
        enable = true;
        name = "eric";
        useSecrets = false;
        fallbackPassword = "il0wwlm?";
        groups = {basic = true; media = true; hardware = true; };
      };
    };
    basePackages.enable = true;
    backupPackages = {
      enable = true;
      protonDrive = {
        enable = true;
        useSecret = false;  # Disable secret usage for now
      };
      monitoring.enable = true;
    };
    # desktop packages moved to modules/home/ - remove this option
  };
  
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia"; #or "intel"
  };

  # System behavior (input/audio)
  hwc.system.services.behavior = {
    enable = true;
    keyboard = {
      enable = true;
      universalFunctionKeys = true;
    };
    audio.enable = true;
  };

  # Login manager for workstation
  hwc.system.services.session.loginManager = {
    enable = true;
    defaultUser = "eric";
    defaultCommand = "Hyprland";
    autoLogin = true;
  };
  
  hwc.infrastructure = {
    hardware = {
      peripherals.printing.enable = true;
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

    session = {
      services.enable = true;

      # Tools/binaries provided by the co-located system parts
      hyprlandTools = {
        enable = true;
        notifications = true;
      };
      waybarTools.enable = true;
    };
  };

  hwc.services.backup.user = {
    enable = true;
    externalDrive.enable = true;
    protonDrive = {
      enable = true;
      useSecret = false;  # Disable secret usage for now
    };
    schedule = {
      enable = true;
      frequency = "daily";
    };
    notifications.enable = true;
  };

  # VALIDATION (by convention):
  # - No Home Manager activation or programs.* here
  # - No modules/home/* HM parts imported here (only system.nix files)
}
