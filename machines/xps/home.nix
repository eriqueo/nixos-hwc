# machines/xps/home.nix
#
# MACHINE: HWC-XPS — Home Manager overrides (HM lane)
# Role home halves (base, desktop) provide defaults via the flake glue;
# this file adjusts only what is unique to this machine.

{ lib, ... }:

{
  # Disable heavyweight apps not needed on this lightweight server/laptop build
  hwc.home.apps = {
    blender.enable = lib.mkForce false;
    freecad.enable = lib.mkForce false;
    obsidian.enable = lib.mkForce false;
    onlyoffice-desktopeditors.enable = lib.mkForce false;
    slack.enable = lib.mkForce false;
    bottles-unwrapped.enable = lib.mkForce false;
  };
}
