{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./home.nix
    ../../profiles/firestick.nix
  ];

  networking.hostName = "hwc-firestick";
  system.stateVersion = "24.05";

  # System-lane requirements for Home Manager modules.
  hwc.system.apps.hyprland.enable = true;
  hwc.system.apps.waybar.enable = true;

  # Tailscale-first networking; keep boot fast in travel scenarios.
  hwc.system.networking = {
    enable = true;
    waitOnline.mode = "off";
    ssh.enable = true;
    tailscale = {
      enable = true;
      extraUpFlags = [ "--ssh" ];
    };
    samba.enable = false;
  };

  # Audio over HDMI is critical; Bluetooth kept for the Firestick remote.
  hwc.system.services.hardware = {
    enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    monitoring.enable = lib.mkForce false;
  };

  # No backups on the travel stick.
  hwc.system.services.backup.enable = lib.mkForce false;
}
