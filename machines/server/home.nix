# machines/server/home.nix
#
# MACHINE: HWC-SERVER — Home Manager one-offs (HM lane)
# CLI defaults come from the base role's home half; the mail menu comes
# from the mail role. Only genuine headless one-offs live here.

{ lib, ... }:

{
  # Mail-health alerts route via hwc-notify only (priority-1 fanout: Discord ×2
  # + email). The old n8n webhook → Slack hop was redundant middleware — the
  # n8n workflow just forwarded to this same :11600/notify — so it was retired
  # 2026-07-09. Leaving webhook.url unset makes send_webhook a no-op.
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

  # `brain <cmd>` — the vault janitor/fixer CLI. The nightly sweep already runs the same
  # checkout through hwc.automation.brainSweep (system lane, one subcommand). This puts the
  # full CLI on PATH for interactive use. Not in the base role: it needs the
  # ~/600_apps/brain checkout and the vault, which only laptop + server carry.
  hwc.home.apps.brain.enable = true;

  # Claude Code: server runs claude from an ad-hoc npm global, so do NOT enable
  # the Nix package/Obsidian-cert here. Opt into the shared, version-controlled
  # skill/agent/command/CLAUDE.md set only — symlinked from ~/.claude-config.
  hwc.home.apps.claude-code.shareConfig = {
    enable = true;
    autoPull.enable = true;  # ff-pull ~/.claude-config from the bare repo (zero-touch receive)
  };

  # T3 Code, headless shape. Same fork and same module as the laptop, minus
  # Electron: `t3 serve` on loopback, fronted by the Caddy vhost
  # t3.hwc.iheartwoodcraft.com (domains/networking/routes.nix), so the phone
  # reaches it over the tailnet while the laptop is off. desktop.enable = false
  # is required, not tidiness — the module asserts the two shapes never coexist,
  # because both would write the same ~/.t3 SQLite store.
  hwc.home.apps.t3code = {
    enable = true;
    desktop.enable = false;
    serve.enable = true;
    serve.port = 3773;
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
