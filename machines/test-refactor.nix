{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/monitoring.nix
    ../modules/services/ntfy.nix
    ../modules/services/transcript-api.nix
  ];
  
  networking.hostName = "test-refactor";
  
  hwc.services.ntfy.enable = true;
  hwc.services.transcriptApi.enable = true;
  
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
  
  system.stateVersion = "24.05";
}
