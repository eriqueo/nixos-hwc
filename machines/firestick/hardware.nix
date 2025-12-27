# Hardware configuration for hwc-firestick (travel TV stick)
# Placeholder: replace with nixos-generate-config output for the target device.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [{
    device = "/var/swapfile";
    size = 2048; # 2GB swap for lightweight usage
  }];

  networking.useDHCP = lib.mkDefault true;

  # Fire TV sticks are ARM64; adjust if targeting different hardware.
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
