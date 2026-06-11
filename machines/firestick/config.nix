{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./home.nix
    # TRANSITIONAL: explicit role-half imports; Phase B replaces these with
    # the flake.nix machines-table resolver. base supplies what firestick.nix
    # previously pulled in via its core.nix import.
    ../../profiles/base/sys.nix
    ../../profiles/appliance/sys.nix
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
