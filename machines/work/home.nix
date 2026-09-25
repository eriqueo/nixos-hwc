# Headless Home Manager lane. Base supplies the CLI and development tools.
{ ... }: {
  hwc.home.theme.graphical = false;

  # Mail role (service split wave 2): this host runs the Proton Bridge session
  # that used to live on hwc-server. mail-health posts to the dispatcher via
  # the default (hwc.notifications.notify.url).

  # The read-only mirrors this machine keeps in Radicale (config.nix
  # hwc.server.services.radicale.mirrors), so hwc_calendar sees them too.
  hwc.mail.calendar.radicale.extraCollections = [ "cto" "proton-work" "google-family" ];

  # khalt (forked khal/ikhal) — supersedes plain khal. Enabled only to
  # materialise the khalt package + ~/.config/khalt/config that the hwc-sys
  # gateway (on this host since wave 2) points HWC_KHAL_BIN / HWC_KHALT_CONFIG at.
  hwc.home.apps.khalt.enable = true;

  # `brain <cmd>` — vault janitor/fixer CLI. Needs ~/600_apps/brain and the
  # vault clone, both present here since service split wave 1.
  hwc.home.apps.brain.enable = true;

  # T3 Code, headless shape — this host's OWN environment, not a move of
  # hwc-server's. Each machine keeps its own ~/.t3 store, signing key and
  # phone pairing; the harness config (~/.claude, ~/.claude-config,
  # ~/.agent-state) is what carries over, via agent-harness. Reached as
  # t3-work.hwc.iheartwoodcraft.com (domains/networking/routes.nix).
  hwc.home.apps.t3code = {
    enable = true;
    desktop.enable = false;
    serve.enable = true;
    serve.port = 3773;
    # Same reasoning as hwc-server: answers on the tailnet (trustedInterfaces
    # carries tailscale0) so the phone can pair by IP; Caddy is the trusted-cert
    # door.
    serve.host = "0.0.0.0";
  };

  # T3 serve and nightly-builds drive the npm-global claude/codex headless;
  # nothing else updates them here.
  hwc.home.apps.agent-harness.cliUpdates.enable = true;
}
