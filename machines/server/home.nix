# machines/server/home.nix
#
# MACHINE: HWC-SERVER — Home Manager one-offs (HM lane)
# CLI defaults come from the base role's home half; the mail menu comes
# from the mail role. Only genuine headless one-offs live here.

{ lib, ... }:

{
  # Headless: no font deployment (overrides nothing today — the desktop
  # role is what turns fonts on — but states the intent explicitly).
  hwc.home.theme.fonts.enable = false;

  # Disable desktop services
  targets.genericLinux.enable = false;
  dconf.enable = lib.mkForce false;
  services.mako.enable = lib.mkForce false;
}
