{ config, lib, pkgs, ... }:
{
  imports = [
    ../etc/nixos/hosts/laptop/hardware-configuration.nix
    ../profiles/base.nix
  ];

  networking.hostName = "laptop";

  hwc.paths = {
    hot = "/home/eric/data";
    media = "/home/eric/media";
  };

  boot.loader.systemd-boot.enable = true;
  system.stateVersion = "24.05";
}
