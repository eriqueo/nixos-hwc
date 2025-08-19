{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware/hwc-laptop.nix
    ../profiles/base.nix
    ../profiles/desktop-hyprland.nix
    ../profiles/security.nix
  ];

  networking.hostName = "hwc-laptop";

  # Laptop-specific settings
  services.thermald.enable = true;
  services.tlp.enable = true;

  # User configuration
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  # Home-manager
  home-manager.users.eric = import ../home/eric.nix;

  system.stateVersion = "24.05";
}
