{ config, lib, pkgs, ... }:
{
  ##############################
  ##  MACHINE: IMMICH-WORKER ##
  ##############################
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = false;

  ##############################
  ##  IMPORTS                 ##
  ##############################
  imports = [
    ./home.nix
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/security.nix
    ../../profiles/workstation.nix
  ];

  ##############################
  ##  SYSTEM IDENTITY         ##
  ##############################
  networking.hostName = "immich-worker";
  hwc.services.vpn.tailscale.enable = true;

  ##############################
  ##  LAPTOP HARDWARE         ##
  ##############################
  services.thermald.enable = true;
  services.tlp.enable = true;

  ##############################
  ##  IMMICH WORKER SERVICES  ##
  ##############################
  fileSystems."/mnt/shared-photos" = {
    device = "hwc-server:/mnt/hot/pictures";
    fsType = "nfs";
    options = [ "rw" "vers=4" ];
  };

  systemd.services.immich-machine-learning = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.immich}/bin/immich-machine-learning";
      Environment = [
        "IMMICH_HOST=100.115.126.41"
        "DATABASE_URL=postgresql://immich_new@100.115.126.41:5432/immich_new"
        "REDIS_HOST=100.115.126.41"
        "REDIS_PORT=6381"
      ];
    };
  };

  ############################################
  ##  FEATURE TOGGLES (HOST OVERRIDES)      ##
  ##  Uncomment/edit to override profiles.  ##
  ############################################
  # hwc.gpu.nvidia = {
  #   enable = true;
  #   prime.enable = true;
  #   prime.nvidiaBusId = "PCI:1:0:0";
  #   prime.intelBusId  = "PCI:0:2:0";
  #   containerRuntime = true;
  # };

  hwc.desktop.waybar.enable = true;

  hwc.desktop.apps = {
    enable = true;
    browser.firefox   = true;
    browser.chromium  = false;
    multimedia.enable = true;
    productivity.enable = true;
  };

  ##############################
  ##  USERS                   ##
  ##############################
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  ##############################
  ##  HOME-MANAGER (USER)     ##
  ##############################

  ##############################
  ##  NIXOS VERSION PIN       ##
  ##############################
  system.stateVersion = "24.05";
}
