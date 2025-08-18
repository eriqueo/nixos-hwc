{ config, lib, pkgs, ... }:
{
  imports = [
    ../etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/monitoring.nix
  ];

  networking.hostName = "server";

  hwc.paths = {
    hot = "/mnt/hot";
    media = "/mnt/media";
  };

  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "24.05";
}
