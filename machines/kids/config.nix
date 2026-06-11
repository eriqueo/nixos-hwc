# machines/kids/config.nix
#
# MACHINE: HWC-KIDS — Retro gaming station for kids (old MacBook Pros)
# Lean setup: browser, eXoDOS, RetroArch, Hyprland. No dev/AI/work bloat.

{ lib, pkgs, ... }:

{
  # Roles (base, gaming) are supplied by the flake.nix machines table —
  # membership lives there, not here. HM config lives in ./home.nix (HM
  # lane), wired by the flake glue.
  imports = [
    ./hardware.nix
  ];

  networking.hostName = "hwc-kids";
  system.stateVersion = "24.05";

  hwc.system.apps.hyprland.enable = true;
  hwc.system.apps.waybar.enable = true;

  # Flatpak: required for eXoDOS emulator bundles (DOSBox, ScummVM, etc.)
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];

  # nix-ld: enabled in profiles/core.nix (all machines)
}
