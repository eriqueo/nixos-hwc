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

  # Service split wave 2: the Proton Bridge session runs on hwc-work. This
  # host's mail consumers still dial 127.0.0.1:1025/1143, which
  # hwc.mail.bridge.relay (config.nix) forwards to hwc-work over the tailnet.
  hwc.mail.bridge.enable = false;

  # khalt + the Radicale mirror collections left with the hwc-sys gateway
  # (their one consumer) for hwc-work in service split wave 2.

  # `brain <cmd>` — the vault janitor/fixer CLI. The nightly sweep already runs the same
  # checkout through hwc.automation.brainSweep (system lane, one subcommand). This puts the
  # full CLI on PATH for interactive use. Not in the base role: it needs the
  # ~/600_apps/brain checkout and the vault, which only laptop + server carry.
  hwc.home.apps.brain.enable = true;

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
    # 0.0.0.0, not loopback, and this matches what hwc-laptop already does:
    # its desktop app runs serverExposureMode = "network-accessible" and its
    # phone pairing is the tailnet IP, not a hostname. The firewall is what
    # bounds this — `trustedInterfaces` carries tailscale0
    # (domains/system/networking/index.nix), so the port answers on the tailnet
    # and nothing forwards it from outside. The Caddy vhost stays as the second
    # door: it is the one with a trusted certificate.
    serve.host = "0.0.0.0";
  };

  # Nothing else updates the npm-global claude and codex here: T3 serve and
  # nightly-builds drive them headless, and ~/.claude.json has autoUpdates=false.
  # Without this, T3 hides every model whose manifest minVersion is newer than
  # the installed CLI.
  hwc.home.apps.agent-harness.cliUpdates.enable = true;

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
