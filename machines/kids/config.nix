# machines/kids/config.nix
#
# MACHINE: HWC-KIDS — Retro gaming station for kids (old MacBook Pros)
# Lean setup: browser, eXoDOS, RetroArch, Hyprland. No dev/AI/work bloat.

{ lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./home.nix
    # TRANSITIONAL: explicit role-half imports; Phase B replaces these with
    # the flake.nix machines-table resolver. base supplies what gaming.nix
    # previously pulled in via its core.nix import.
    # NOTE: gaming listed before base to preserve the old list-merge order
    # (a module's own definitions merge before its imports', so gaming.nix's
    # nix-ld libs historically preceded core.nix's). Phase B normalizes this.
    ../../profiles/gaming/sys.nix
    ../../profiles/base/sys.nix
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
