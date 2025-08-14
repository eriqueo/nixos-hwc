{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/media.nix
    ../profiles/monitoring.nix
    ../modules/services/caddy.nix
  ];
  
  networking.hostName = "media-test";
  
  hwc.services.caddy.enable = true;
  
  hwc.storage.hot.device = "/dev/disk/by-uuid/YOUR-HOT-UUID";
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "media" ];
  };
  
  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "24.05";
}
