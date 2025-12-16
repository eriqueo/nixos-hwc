# Hardware configuration for hwc-gaming (SBC Gaming Console)
# PLACEHOLDER - Replace with 'nixos-generate-config' output when SBC hardware is available
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Placeholder boot configuration - will be replaced by actual SBC hardware
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Placeholder filesystem configuration
  # Replace with actual SBC disk UUIDs when hardware is available
  fileSystems."/" =
    { device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  # Small swap for SBC (4GB)
  swapDevices = [{
    device = "/var/swapfile";
    size = 4096; # 4GB in MB
  }];

  # Network configuration
  networking.useDHCP = lib.mkDefault true;

  # Platform - change to aarch64-linux for ARM SBCs (Raspberry Pi, Orange Pi, etc.)
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # NOTE: For ARM SBCs (Raspberry Pi 5, Orange Pi, etc.), change to:
  # nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
