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
    id        = "discord-hwc-leads";
    # Stable audit id retained across the #hwc-leads → #leads rename.
    name      = "#leads (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-hwc-leads";
    params = {
      username  = "HWC Leads";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-nightly-builds";
    # Stable audit id retained across the #nightly-builds → #builds rename.
    name      = "#builds (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-nightly-builds";
    params = {
      username  = "HWC Nightly Builds";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-media";
    name      = "#media (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-media";
    params = {
      username  = "HWC Media";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-frigate";
    # Stable audit id retained across the #frigate → #cameras rename.
    name      = "#cameras (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-frigate";
    params = {
      username  = "HWC Cameras";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-ops";
    name      = "#ops (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-ops";
    params = {
      username  = "HWC Ops";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-website";
    name      = "#website (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-website";
    params = {
      username  = "HWC Website";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-finance";
    name      = "#finance (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-finance";
    params = {
      username  = "HWC Finance";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-events";
    name      = "#events (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-events";
    params = {
      username  = "HWC Events";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-home-scout";
    name      = "#home-scout (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-home-scout";
    params = {
      username  = "Home Scout";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-research-scout";
    name      = "#research-scout (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-research-scout";
    params = {
      username  = "Research Scout";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-lead-scout";
    name      = "#lead-scout (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-lead-scout";
    params = {
      username  = "Lead Scout";
      timeoutMs = 5000;
    };
  }

  {
    id        = "discord-canary";
    name      = "#canary (Discord)";
    adapter   = "discord";
    secretRef = "discord-webhook-canary";
    params = {
      username  = "HWC Delivery Canary";
      timeoutMs = 5000;
    };
  }

  # SMTP via Proton Bridge on loopback. Bridge listens on 127.0.0.1:1025
  # for local clients; auth is PLAIN with the proton-bridge-password
  # agenix secret (Proton Bridge shares one password across every address
  # on the account, so the same secret authenticates office@ and eric@).
  #
  # from = office@, to = eric@: sending FROM a different address than the
  # recipient stops Proton from applying its sent-mail auto-archive to the
  # message, so criticals land in Eric's Inbox instead of Archive. Derived
  # from the working `proton-office` msmtp account (domains/mail/accounts).
  {
    id        = "smtp-office";
    name      = "email office@ → eric@iheartwoodcraft.com (SMTP / Proton Bridge)";
    adapter   = "smtp";
    secretRef = "proton-bridge-password";
    params = {
      host       = "127.0.0.1";
      port       = 1025;
      # No STARTTLS on loopback — matches the ONLY proven-working Proton
      # Bridge SMTP config on this host, the `proton-office` msmtp account
      # (`tls off; tls_starttls off`). The prior requireTls=true was never
      # exercised (0 priority=1 dispatches in the audit history), so there
      # was no working baseline to preserve.
      requireTls = false;
      # Bridge auths against the *send address*. Confirmed against the
      # working msmtp account `proton-office` (user office@iheartwoodcraft.com).
      login      = "office@iheartwoodcraft.com";
      from       = "office@iheartwoodcraft.com";
      to         = "eric@iheartwoodcraft.com";
      timeoutMs  = 10000;
    };
  }
]
