# machines/xps/home.nix
#
# MACHINE: HWC-XPS — Home Manager overrides (HM lane)
# Role home halves (base, desktop) provide defaults via the flake glue;
# this file adjusts only what is unique to this machine.

{ inputs, lib, pkgs, ... }:

{
  # Disable heavyweight apps not needed on this lightweight server/laptop build
  hwc.home.apps = {
    blender.enable = lib.mkForce false;
    freecad.enable = lib.mkForce false;
    obsidian.enable = lib.mkForce false;
    onlyoffice-desktopeditors.enable = lib.mkForce false;
    slack.enable = lib.mkForce false;
    bottles-unwrapped.enable = lib.mkForce false;

    # XPS stays on nixpkgs-stable, which no longer packages Electron 43, while
    # the T3 Code desktop bundle is compiled against Electron 43.4.1. Use the
    # same locked unstable input as hwc-laptop so the runtime major remains 43.
    # REMOVE WHEN: apps/desktop/package.json moves to a major packaged by the
    # locked stable input; then restore the module default and run the XPS eval.
    t3code.desktop.electronPackage =
      inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.electron_43;
  };
}
