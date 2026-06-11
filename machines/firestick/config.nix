{ config, lib, pkgs, ... }:

{
  # Roles (base, appliance) are supplied by the flake.nix machines table —
  # membership lives there, not here. HM config lives in ./home.nix (HM
  # lane), wired by the flake glue.
  imports = [
    ./hardware.nix
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
  hwc.system.hardware = {
    enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    monitoring.enable = lib.mkForce false;
  };

  # No backups on the travel stick.
  hwc.data.backup.enable = lib.mkForce false;
}
