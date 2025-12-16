{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix                    # Auto-generated when SBC available
    ./home.nix                        # Home Manager activation
    ../../profiles/system.nix         # Base system (users, shell, hardware)
    ../../profiles/gaming.nix         # Gaming profile
  ];

  # Machine identity
  networking.hostName = "hwc-gaming";
  system.stateVersion = "24.05";

  # Storage paths for ROMs
  hwc.paths = {
    hot = "/home/eric/gaming";        # Local storage (SD card)
    media = "/mnt/network-roms";      # Network mount (optional)
  };

  # Enable Samba for ROM transfer over network
  hwc.networking.samba = {
    enable = true;
    shares.roms = {
      path = "${config.hwc.paths.hot}/roms";
      browseable = true;
      readOnly = false;
    };
  };

  # Optional: NFS mount for network ROM library
  # Disabled by default - enable when needed
  fileSystems."/mnt/network-roms" = lib.mkIf false {
    device = "server.local:/mnt/media/retro-roms";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
      "soft"
    ];
  };
}
