# MS-02 dual boot: Linux uses p6 (HWCWORK) and its own p5 ESP (HWCBOOT).
# Windows and its EFI/recovery partitions remain on p1-p4. Labels were checked
# against the installed system; hardware settings follow its generated config.
{ config, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usbhid" "usb_storage" "uas" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/HWCWORK";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/HWCBOOT";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [{ device = "/var/swapfile"; size = 16384; }];
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.npu.enable = true;

  # Wi-Fi is this host's only uplink (Intel BE20x, firmware 101). On a Wi-Fi 7
  # multi-link association (6 GHz, 320 MHz) the firmware asserted under
  # sustained load — ADVANCED_SYSASSERT 0x4449 + LMAC fatal NMI, 7 resets from
  # 2026-09-25 17:40, none before — dropping the tunnel and tailnet each time.
  # Pin the card to Wi-Fi 6E (no EHT/MLO; 6 GHz at 160 MHz), far above what
  # the host needs. Revisit on a newer iwlwifi firmware or a wired uplink.
  boot.extraModprobeConfig = ''
    options iwlwifi disable_11be=1
  '';
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
