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
  # Criticals also page via hwc-notify (priority-1 fanout: Discord ×2 + email).
  hwc.mail.health.notify.url = "http://127.0.0.1:11600";

  # Calendar → Radicale (self-hosted CalDAV, same backend as tasks). Retires
  # the iCloud account pairs the mail role declares (vdirsyncer no longer
  # generates them once radicale is on). This gives hwc-server the
  # calendars-radicale/ vdir the MCP's hwc_calendar tool reads.
  hwc.mail.calendar.radicale.enable = true;

  # khalt (forked khal/ikhal) — supersedes plain khal. Headless server enables
  # it only to materialise the khalt package + ~/.config/khalt/config that the
  # MCP gateway points HWC_KHAL_BIN / HWC_KHALT_CONFIG at. No TUI use here.
  hwc.home.apps.khalt.enable = true;

  # Claude Code: server runs claude from an ad-hoc npm global, so do NOT enable
  # the Nix package/Obsidian-cert here. Opt into the shared, version-controlled
  # skill/agent/command/CLAUDE.md set only — symlinked from ~/.claude-config.
  hwc.home.apps.claude-code.shareConfig = {
    enable = true;
    autoPull.enable = true;  # ff-pull ~/.claude-config from the bare repo (zero-touch receive)
  };

  # Headless: no font deployment (overrides nothing today — the desktop
  # role is what turns fonts on — but states the intent explicitly).
  hwc.home.theme.fonts.enable = false;

  # Headless: skip the GUI-only XCursor theme (~846 MB) — nothing renders
  # a pointer on this box. Graphical machines keep the default (true).
  hwc.home.theme.graphical = false;

  # Disable desktop services
  targets.genericLinux.enable = false;
  dconf.enable = lib.mkForce false;
  services.mako.enable = lib.mkForce false;
}
