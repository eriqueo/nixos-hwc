# domains/notifications/notify/options.nix
#
# Schema for hwc.notifications.notify.*
#
# Charter Law 2: namespace = folder. Charter Law 3: no hardcoded paths
# outside domains/paths/. Charter Law 4: service runs as eric:users.

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.notifications.notify = {
    enable = lib.mkEnableOption ''
      hwc-notify — hexagonal notification dispatcher.
      Routes Notifications to Discord + SMTP via pluggable adapters,
      with circuit breakers per channel and an audit log of every
      delivery attempt. Replaces the n8n alert-manager workflow and
      the per-script CLI senders (hwc-gotify-send, hwc-webhook-send).
      See ~/.claude/plans/hashed-snacking-crab.md.
    '';

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Service user (Charter Law 4: native services run as eric:users).";
    };

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind the HTTP listener. Default loopback-only; external
        access goes via Caddy on the reverseProxyPort.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11600;
      description = "TCP port for the HTTP listener.";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 29443;
      description = ''
        External Caddy port for tailnet access. Loopback daemon is on
        bindAddr:port; Caddy fronts it on this port using the tailnet cert.
      '';
    };

    statePath = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/notify";
      description = ''
        Directory holding service state (audit log SQLite DB, dedup cache).
        systemd StateDirectory creates this owned by user:users at 0750.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Minimum severity for structured JSON log output.";
    };

    # ── Channel secret references ─────────────────────────────────────────
    # Phase 1.2: only the alerts channel has live wiring. leads channel
    # follows when Phase 2 needs it. Both reference the agenix secret IDs
    # declared in domains/secrets/declarations/services.nix.
    channels = {
      discordAlerts.secretRef = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "discord-webhook-hwc-alerts";
        description = ''
          agenix secret name (not file path) holding the Discord webhook URL
          for the #hwc-alerts channel. Resolved at module-eval to
          `config.age.secrets.<ref>.path`. Set to null to disable the
          channel (falls back to log-only at runtime).
        '';
      };
    };
  };
}
