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

  # ===================================================================
  # HWC SAFETY CONFIGURATION
  # ===================================================================

  # 1. Set the fallback password for your main user.
  # This is used if hwc.home.user.useSecrets is set to false.
  hwc.home.user.fallbackPassword = "il0wwlm?";

  # 2. Enable the emergency root user for the migration.
  # You should set this to 'false' after you confirm the system works.
  hwc.security.emergencyAccess.enable = true;
  hwc.security.emergencyAccess.password = "il0wwlm?";

  # 3. Ensure the path to this machine's age key is correct.
  hwc.security.ageKeyFile = ../../secrets/keys.txt; # Or specific key for this host
  ##############################
  ##  NIXOS VERSION PIN       ##
  ##############################
  system.stateVersion = "24.05";
}
