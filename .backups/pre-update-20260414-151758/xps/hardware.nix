# nixos-hwc/machines/xps/hardware.nix
#
# Hardware configuration for Dell XPS 2018 (hwc-xps)
# This is a PLACEHOLDER - will be generated during NixOS installation
# Run: nixos-generate-config --show-hardware-config > /tmp/hardware.nix
# Then copy relevant sections below
#
# IMPORTANT: Update this file during installation with actual hardware detection results

{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Dell XPS 2018 typical kernel modules (8th gen Intel)
  # These will be auto-detected during installation
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Bootloader configuration (UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem
  # TODO: Update UUID during installation
  # Run: lsblk -f or blkid to get UUID
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-ROOT-UUID";
    fsType = "ext4";
  };

  # Boot filesystem (EFI)
  # TODO: Update UUID during installation
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Hot storage (remaining space on 1TB internal SSD)
  # TODO: Update UUID during installation
  # Partition layout: ~100GB root, ~1GB boot, remainder for /mnt/hot
  fileSystems."/mnt/hot" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-HOT-UUID";
    fsType = "ext4";
  };

  # Media storage (external DAS with 2x3TB HDDs)
  # TODO: Configure during installation
  # Options: Single drive, RAID1 mirror, or separate volumes
  # Using by-label for flexibility (can be changed to by-uuid)
  # fileSystems."/mnt/media" = {
  #   device = "/dev/disk/by-label/media";  # Or by-uuid after setup
  #   fsType = "ext4";
  # };
  # NOTE: This is defined in config.nix for visibility

  # Backup storage (external DAS partition)
  # TODO: Configure during installation
  # fileSystems."/mnt/backup" = {
  #   device = "/dev/disk/by-label/backup";  # Or by-uuid after setup
  #   fsType = "ext4";
  # };
  # NOTE: This is defined in config.nix for visibility

  # Swap file for laptop (16GB recommended for 8-16GB RAM)
  # Located on root filesystem
  swapDevices = [{
    device = "/var/swapfile";
    size = 16384;  # 16GB in MB
  }];

  # Networking - DHCP on all interfaces
  networking.useDHCP = lib.mkDefault true;
  # Specific interfaces will be auto-detected:
  # networking.interfaces.wlp2s0.useDHCP = lib.mkDefault true;  # WiFi
  # networking.interfaces.enp0s31f6.useDHCP = lib.mkDefault true;  # Ethernet (if present)

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Intel CPU microcode updates (8th gen - Coffee Lake)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Dell XPS specific hardware support (optional, uncomment if needed)
  # Uncomment if using nixos-hardware module:
  # imports = [ (modulesPath + "/../nixos-hardware/dell/xps/15-9570") ];
  # Or for XPS 13:
  # imports = [ (modulesPath + "/../nixos-hardware/dell/xps/13-9370") ];
}
