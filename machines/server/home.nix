# machines/server/home.nix
#
# MACHINE: HWC-SERVER — Home Manager one-offs (HM lane)
# CLI defaults come from the base role's home half; the mail menu comes
# from the mail role. Only genuine headless one-offs live here.

{ lib, ... }:

{
  # Mail-health webhook endpoint — names this machine (Law 16 keeps
  # hostnames out of roles; the rest of the mail menu is in the mail role).
  hwc.mail.health.webhook.url = "https://hwc-server.ocelot-wahoo.ts.net:10000/webhook/mail-health";

  # Headless: no font deployment (overrides nothing today — the desktop
  # role is what turns fonts on — but states the intent explicitly).
  hwc.home.theme.fonts.enable = false;

  # Disable desktop services
  targets.genericLinux.enable = false;
  dconf.enable = lib.mkForce false;
  services.mako.enable = lib.mkForce false;
}
