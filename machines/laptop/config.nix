{ config, lib, pkgs, ... }:
{
  ##############################
  ##  MACHINE: HWC-LAPTOP    ##
  ##############################

  ##############################
  ##  IMPORTS                 ##
  ##############################
  imports = [
    ./home.nix
    ./hardware.nix
    .../profiles/base.nix
    .../profiles/security.nix
    .../profiles/workstation.nix
  ];

  ##############################
  ##  SYSTEM IDENTITY         ##
  ##############################
  networking.hostName = "hwc-laptop";

  ##############################
  ##  LAPTOP HARDWARE         ##
  ##############################
  services.thermald.enable = true;
  services.tlp.enable = true;

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
