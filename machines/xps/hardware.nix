# nixos-hwc/machines/xps/hardware.nix
#
# Hardware configuration for Dell XPS 2018 (hwc-xps)
# Generated from working system 2026-04-16

{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Boot modules retained from the working 8th-generation Intel system.
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

  # The TerraMaster's two 3TB drives form the ZFS media-pool mirror.
  # config.nix imports it; the dataset owns /mnt/media. Do not add an ext4
  # mount here. Neither a separate hot partition nor a backup volume exists.

  # 16GB swap file on the SSD; this machine has 32GB RAM.
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
