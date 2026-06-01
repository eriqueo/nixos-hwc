# domains/business/leads/options.nix
#
# Schema for hwc.business.leads.*
#
# Charter Law 2: namespace = folder. Charter Law 3: no hardcoded paths
# outside domains/paths/. Charter Law 4: service runs as eric:users.

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.business.leads = {
    enable = lib.mkEnableOption ''
      hwc-leads — unified lead pipeline.
      Single POST /leads HTTP endpoint replacing the three calculator /
      contact / appointment webhook paths. Validates → JT graph → DB →
      hwc-notify ping → customer email. See
      ~/.claude/plans/hashed-snacking-crab.md for the design.
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
      default = 11650;
      description = "TCP port for the HTTP listener.";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 30443;
      description = ''
        External Caddy port for tailnet access. Loopback daemon is on
        bindAddr:port; Caddy fronts it on this port using the tailnet cert.
      '';
    };

    statePath = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/leads";
      description = ''
        Directory holding service state (audit log SQLite DB, JT-retry queue).
        systemd StateDirectory creates this owned by user:users at 0750.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Minimum severity for structured JSON log output.";
    };

    # ── Postgres ─────────────────────────────────────────────────────────
    # Canonical Lead records land in hwc.calculator_leads (extended by
    # parts/migrations/001-canonical-lead-extensions.sql). Default DSN
    # uses Unix-socket peer auth as the service user — no password file
    # needed.
    postgresDsn = lib.mkOption {
      type = lib.types.str;
      default = "postgresql:///hwc";
      description = ''
        libpq connection string for the heartwood_business database.
        Default: socket peer auth as the service user (eric). Override
        per machine if Postgres moves off the local socket.
      '';
    };

    # ── Downstream service refs ──────────────────────────────────────────
    # hwc-leads calls hwc-notify for the new-lead pings. Loopback today;
    # would change if hwc-notify ever moves off-host.
    notifyServiceUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11600";
      description = ''
        Base URL of the hwc-notify service. The Phase 2 NotifyAdapter
        POSTs to <notifyServiceUrl>/notify with a server-built
        Notification payload.
      '';
    };

    # ── Secrets ──────────────────────────────────────────────────────────
    # HMAC for POST /leads request signing. The calc app + 11ty form
    # carry the same secret (built into their bundle); the service
    # verifies the X-HWC-Signature header before touching core.
    hmacSecretRef = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "hwc-leads-hmac-secret";
      description = ''
        agenix secret name holding the HMAC signing key used by POST
        /leads. Resolved at module-eval to
        config.age.secrets.<ref>.path. Set to null to disable HMAC
        verification (DEV ONLY — always set in prod).

        SHARED SECRET — the same agenix entry is also read by the n8n
        container (see hwc.automation.n8n.secrets.hwcLeadsHmacFile and
        the calculator_lead thin-shell workflow). Rotating it requires
        BOTH services to restart with the new bytes:
          - hwc-leads picks up the new value on next start; the
            restartTriggers below trigger that on `nixos-rebuild
            switch`.
          - n8n needs an explicit `systemctl restart podman-n8n.service`
            after rotation because the container's secrets env-file is
            populated at unit-start, not on age secret remount.
        Half-rotations silently 401 every lead submission until the
        startup self-test catches it on the next restart.
      '';
    };

    # JT credentials — same agenix secret the existing n8n workflow uses.
    jtGrantKeyRef = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "jobtread-grant-key";
      description = ''
        agenix secret name for the JobTread grant key. Phase 2.4 reads
        it at startup for the JT GraphQL Pave client.
      '';
    };

    # ── Customer email (Phase 2.5) ───────────────────────────────────────
    # Outbound email to the lead's address ("thanks for your inquiry").
    # Routed via Proton Bridge on loopback — same path hwc-notify uses
    # for its smtp-eric channel. The agenix secret is shared.
    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP host. Default = Proton Bridge on loopback.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 1025;
        description = "SMTP port.";
      };
      requireTls = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require STARTTLS. Bridge requires it even on loopback.";
      };
      login = lib.mkOption {
        type = lib.types.str;
        default = "eric@iheartwoodcraft.com";
        description = "SMTP AUTH login. Bridge auths on the send address.";
      };
      from = lib.mkOption {
        type = lib.types.str;
        default = "eric@iheartwoodcraft.com";
        description = "From header for the customer-confirmation email.";
      };
      passwordSecretRef = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "proton-bridge-password";
        description = ''
          agenix secret name for the SMTP password. Defaults to the
          same Bridge password hwc-notify's smtp-eric channel uses.
          Set to null to disable customer-email entirely.
        '';
      };
    };
  };
}
