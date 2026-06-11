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

  # Audio over HDMI is critical; Bluetooth kept for the Firestick remote.
  # (Networking/backup/monitoring trim comes from the appliance role.)
  hwc.system.hardware = {
    audio.enable = true;
    bluetooth.enable = true;
  };
}
