# nixos-hwc/profiles/workstation.nix
#
# WORKSTATION PROFILE - NixOS orchestration only (v6)
# Imports system/infrastructure/services modules. No Home Manager here.

{ lib, ... }:
{
  imports = [
    # System
    ../modules/system/users.nix
    ../modules/system/security/sudo.nix
    ../modules/system/base-packages.nix
    ../modules/system/backup-packages.nix
    ../modules/system/desktop-packages.nix
    ../modules/system/audio.nix

    # Infrastructure
    ../modules/infrastructure/gpu.nix
    ../modules/infrastructure/printing.nix
    ../modules/infrastructure/virtualization.nix
    ../modules/infrastructure/samba.nix
#    ../modules/infrastructure/user-services.nix
    ../modules/infrastructure/user-hardware-access.nix
    ../modules/infrastructure/storage.nix

    # Services
    ../modules/services/backup/user-backup.nix

    # Co-located app system parts (NixOS modules exporting infra tools)
    ../modules/home/apps/hyprland/parts/system.nix
    ../modules/home/apps/waybar/parts/system.nix
  ];

  hwc.system = {
    users.enable = true;
    user = {
      enable = true;
      name = "eric";
      useSecrets = false;
      fallbackPassword = "il0wwlm?";
      groups = {basic = true; media = true; hardware = true; };
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
    desktop.enable = true;
    audio.enable = true;
  };
  
  hwc.gpu = {
    enable = true;
    type = "nvidia"; #or "intel"
  };
  
  hwc.infrastructure = {
    printing.enable = true;
    virtualization.enable = true;
    samba.enableSketchupShare = true;
    userServices.enable = true;
    storage = {
      backup = {
        enable = true;
        externalDrive.autoMount = true;
      };
    };

    userHardwareAccess = {
      enable = true;
      groups = {
        media = true;
        development = true;
        virtualization = true;
        hardware = true;
      };
    };

    # Tools/binaries provided by the co-located system parts
    hyprlandTools = {
      enable = true;
      notifications = true;
    };
    waybarTools.enable = true;
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
