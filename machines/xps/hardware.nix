# nixos-hwc/machines/xps/hardware.nix
#
# Hardware configuration for Dell XPS 2018 (hwc-xps)
# Generated from working system 2026-04-16

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

  # Root filesystem (nvme0n1p2)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/c58554d0-1a3f-4d28-bf14-e6d8619f5fe2";
    fsType = "ext4";
  };

  # Boot filesystem (EFI, nvme0n1p1)
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8825-A4DE";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Hot storage — XPS has no separate hot partition
  # /mnt/hot is a directory on root, managed via hwc.system.mounts.hot.enable = false in config.nix

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
