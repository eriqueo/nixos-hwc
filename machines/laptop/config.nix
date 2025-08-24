{ config, lib, pkgs, ... }:
{
  ##############################
  ##  MACHINE: HWC-LAPTOP    ##
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
  networking.hostName = "hwc-laptop";
  hwc.services.vpn.tailscale.enable = false;
  ##############################
  ##  LAPTOP HARDWARE         ##
  ##############################
  services.thermald.enable = true;
  services.tlp.enable = true;

  ############################################
  ##  FEATURE TOGGLES (HOST OVERRIDES)      ##
  ##  Uncomment/edit to override profiles.  ##
  ############################################

  # GPU Configuration
  hwc.gpu.type = "nvidia";
  hwc.gpu.nvidia = {
    prime.enable = true;
    prime.nvidiaBusId = "PCI:1:0:0";
    prime.intelBusId = "PCI:0:2:0";
    containerRuntime = true;
  };

  hwc.desktop.waybar.enable = true;
  hwc.secrets.enable = true;
   hwc.desktop.apps = {
    enable = true;
     browser.firefox   = true;
     browser.chromium  = false;
     multimedia.enable = true;
     productivity.enable = true;
   };
   # Enable SSH via the user module
   hwc.home.ssh.enable = true;

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
