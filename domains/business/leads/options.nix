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
  };
}
