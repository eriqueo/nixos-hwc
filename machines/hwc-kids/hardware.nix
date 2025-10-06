# Hardware configuration for hwc-kids
# Generated from this machine's reality; adapted for flake usage.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    # From your earlier `lsblk` on this box:
    device = "/dev/disk/by-uuid/c58554d0-1a3f-4d28-bf14-e6d8619f5fe2";
    fsType  = "ext4";
  };

  fileSystems."/boot" = {
    # ESP UUID from this box:
    device = "/dev/disk/by-uuid/8825-A4DE";
    fsType  = "vfat";
    # Match your repo style (laptop used fmask/dmask 0022). If you prefer root-only, use "umask=0077".
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  # DHCP defaults (same pattern as laptop).
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.<ifname>.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
