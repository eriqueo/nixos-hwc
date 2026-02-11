# machines/xps/home.nix
#
# MACHINE: HWC-XPS — Home Manager overrides
# Machine-specific HM option overrides. Profiles/home.nix provides defaults;
# this file adjusts only what is unique to this machine.

{ lib, ... }:

{
  home-manager.users.eric = {

    # Disable heavyweight apps not needed on this lightweight server/laptop build
    hwc.home.apps = {
      blender.enable = lib.mkForce false;
      freecad.enable = lib.mkForce false;
      obsidian.enable = lib.mkForce false;
      onlyoffice-desktopeditors.enable = lib.mkForce false;
      slack.enable = lib.mkForce false;
      bottles-unwrapped.enable = lib.mkForce false;
    };

  };
}
