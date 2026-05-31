# domains/notifications/notify/parts/channels.nix
#
# Default channel registry — pure data, no NixOS module options here.
# Imported by index.nix and merged with hwc.notifications.notify.channels
# overrides at module-eval time.
#
# Each row is:
#   { id        — stable channel id (also keyed in audit log)
#     name      — human label for logs / introspection
#     adapter   — "discord" | "log-only"  (new adapters: extend ChannelConfigSchema)
#     secretRef — agenix secret name (NOT a path); resolved at module-eval
#                 to /run/agenix/<ref> via config.age.secrets.<ref>.path
#     params    — adapter-specific knobs
#   }
#
# The Discord webhook URL never appears in this file — only the secret REF.

[
  {
    id        = "discord-hwc-alerts";
    name      = "#hwc-alerts (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-hwc-alerts";
    params = {
      username  = "HWC Alerts";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-hwc-leads";
    name      = "#hwc-leads (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-hwc-leads";
    params = {
      username  = "HWC Leads";
      timeoutMs = 5000;
    };
  }

  # SMTP via Proton Bridge on loopback. Bridge listens on 127.0.0.1:1025
  # without TLS for local clients (per the existing msmtp config); auth
  # is PLAIN with the proton-bridge-password agenix secret.
  {
    id        = "smtp-eric";
    name      = "email → eric@iheartwoodcraft.com (SMTP / Proton Bridge)";
    adapter   = "smtp";
    secretRef = "proton-bridge-password";
    params = {
      host       = "127.0.0.1";
      port       = 1025;
      requireTls = false;
      login      = "eric@iheartwoodcraft.com";
      from       = "eric@iheartwoodcraft.com";
      to         = "eric@iheartwoodcraft.com";
      timeoutMs  = 10000;
    };
  }
]
