# domains/business/leads/index.nix
#
# hwc-leads — unified lead pipeline.
#
# Phase 2.1: minimal HTTP server with /health only. Subsequent chunks
# add the Lead Zod schema, JT GraphQL Pave adapter, Postgres adapter,
# hwc-notify client, customer-email path, HMAC auth, MCP tool, and
# the contact-form + calculator cutover.
#
# Same hexagonal layout + deployment shape as hwc-notify (the Phase 1
# template): pkgs.buildNpmPackage, hexagonal core/ports/adapters,
# systemd unit with Charter hardening, Caddy port-mode route, shared
# domains/lib/deps-update.nix CLI for the npmDepsHash dance.
#
# See ~/.claude/plans/hashed-snacking-crab.md for the full design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.leads;
  paths = config.hwc.paths;

  # Hermetic Nix-built derivation. Reads parts/src/{package,package-lock}.json
  # to fetch deps offline (against npmDepsHash) and runs `npm run build`.
  hwc-leads-pkg = pkgs.buildNpmPackage {
    pname = "hwc-leads";
    version = "0.1.0";

    src = lib.cleanSourceWith {
      src = ./parts/src;
      filter = path: type:
        let base = baseNameOf path;
        in base != "node_modules" && base != "dist" && base != ".gitignore";
    };

    # First-time setup: lib.fakeHash → nixos-rebuild fails with real hash
    # → paste here → rebuild succeeds. Future updates: `hwc-leads-deps-update`.
    npmDepsHash = "sha256-Kc7OXCtRHWTM63Lddbss51Wd+VVKHcSczolh8v3JkeY=";

    npmBuildScript = "build";
    dontNpmPrune = false;
  };

  mainJs = "${hwc-leads-pkg}/lib/node_modules/hwc-leads/dist/main.js";

  # JT mappings — pure data file with HWC's JT organization ID, custom
  # field IDs, default location. Serialised to JSON via pkgs.writeText
  # and exposed to the runtime as HWC_LEADS_JT_MAPPINGS_FILE.
  jtMappingsJson = builtins.toJSON (import ./parts/jt-mappings.nix);
  jtMappingsFile = pkgs.writeText "hwc-leads-jt-mappings.json" jtMappingsJson;

  # Shared deps-update wrapper, parameterised for this service.
  leads-deps-update = (import ../../lib/deps-update.nix { inherit pkgs config; }) {
    serviceName = "hwc-leads";
    serviceRel  = "domains/business/leads";
  };
in
{
  #========================================================================
  # OPTIONS
  #========================================================================
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

    # ── Ingress rate limit ──────────────────────────────────────────────
    # In-memory sliding window keyed on the validated LeadInput source
    # ("calculator" / "contact" / "appointment"). Absorbs misconfigured
    # n8n retry loops + webhook replay storms at the HTTP boundary.
    # Per-process state — resets on service restart.
    rateLimit = {
      maxPerWindow = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = ''
          Maximum POST /leads requests per source per window before the
          429 cap kicks in. Applies independently to each source value.
        '';
      };
      windowSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = ''
          Sliding-window length in seconds. Default is 60 — together
          with maxPerWindow=10 this means up to ten lead submissions
          per minute per source.
        '';
      };
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

  config = lib.mkIf cfg.enable {

    #========================================================================
    # SYSTEMD SERVICE
    #========================================================================
    systemd.services.hwc-leads = {
      description = "hwc-leads — unified lead pipeline";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Restart on rotation of any consumed secret. Same pattern as
      # notify; see reference_agenix_rotate_needs_restart in memory.
      restartTriggers = builtins.filter (x: x != null) [
        (if cfg.hmacSecretRef != null
         then config.age.secrets.${cfg.hmacSecretRef}.file
         else null)
        (if cfg.jtGrantKeyRef != null
         then config.age.secrets.${cfg.jtGrantKeyRef}.file
         else null)
        (if cfg.smtp.passwordSecretRef != null
         then config.age.secrets.${cfg.smtp.passwordSecretRef}.file
         else null)
      ];

      environment = {
        HWC_LEADS_BIND_ADDR           = cfg.bindAddr;
        HWC_LEADS_PORT                = toString cfg.port;
        HWC_LEADS_STATE_DIR           = cfg.statePath;
        HWC_LEADS_LOG_LEVEL           = cfg.logLevel;
        HWC_LEADS_NOTIFY_URL          = cfg.notifyServiceUrl;
        HWC_LEADS_PG_DSN              = cfg.postgresDsn;
        HWC_LEADS_JT_MAPPINGS_FILE    = "${jtMappingsFile}";
        HWC_LEADS_SMTP_HOST           = cfg.smtp.host;
        HWC_LEADS_SMTP_PORT           = toString cfg.smtp.port;
        HWC_LEADS_SMTP_REQUIRE_TLS    = if cfg.smtp.requireTls then "1" else "0";
        HWC_LEADS_SMTP_LOGIN          = cfg.smtp.login;
        HWC_LEADS_SMTP_FROM           = cfg.smtp.from;
        HWC_LEADS_RATE_LIMIT_MAX_PER_WINDOW = toString cfg.rateLimit.maxPerWindow;
        HWC_LEADS_RATE_LIMIT_WINDOW_SECONDS = toString cfg.rateLimit.windowSeconds;
      } // lib.optionalAttrs (cfg.hmacSecretRef != null) {
        HWC_LEADS_HMAC_FILE = config.age.secrets.${cfg.hmacSecretRef}.path;
      } // lib.optionalAttrs (cfg.jtGrantKeyRef != null) {
        HWC_LEADS_JT_GRANT_FILE = config.age.secrets.${cfg.jtGrantKeyRef}.path;
      } // lib.optionalAttrs (cfg.smtp.passwordSecretRef != null) {
        HWC_LEADS_SMTP_PASSWORD_FILE = config.age.secrets.${cfg.smtp.passwordSecretRef}.path;
      } // {
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        # --experimental-sqlite enables node:sqlite for the (future)
        # audit log — same pattern as hwc-notify. Drop both flags when
        # node:sqlite ships stable.
        ExecStart = "${pkgs.nodejs_22}/bin/node --experimental-sqlite --no-warnings ${mainJs}";
        User = lib.mkForce cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";

        StateDirectory = "hwc/leads";
        StateDirectoryMode = "0750";

        # Hardening — mirrors hwc-notify / persona-daemon / brain-mcp.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [ cfg.statePath ];
      };
    };

    # Expose the leads CLIs on the system PATH.
    environment.systemPackages = [ leads-deps-update ];

    #========================================================================
    # CADDY REVERSE PROXY — port mode over tailnet
    #========================================================================
    hwc.networking.shared.routes = [{
      name = "hwc-leads";
      mode = "vhost";
      upstream = "http://${cfg.bindAddr}:${toString cfg.port}";
    }];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "hwc.business.leads.user must not be root (Charter Law 4).";
      }
      {
        assertion = cfg.port != cfg.reverseProxyPort;
        message = "hwc.business.leads.port and reverseProxyPort must differ.";
      }
      {
        # If an HMAC secretRef is configured, the agenix secret must exist.
        assertion =
          cfg.hmacSecretRef == null
          || (config.age.secrets ? ${cfg.hmacSecretRef});
        message = ''
          hwc.business.leads.hmacSecretRef = "${toString cfg.hmacSecretRef}"
          but no matching agenix secret is declared in
          domains/secrets/declarations/. Either declare the secret or
          set hmacSecretRef = null (dev only).
        '';
      }
      {
        # JT grant key — same shape.
        assertion =
          cfg.jtGrantKeyRef == null
          || (config.age.secrets ? ${cfg.jtGrantKeyRef});
        message = ''
          hwc.business.leads.jtGrantKeyRef = "${toString cfg.jtGrantKeyRef}"
          but no matching agenix secret is declared. Either declare or
          set to null (the service will refuse JT-creation calls).
        '';
      }
      {
        # SMTP password — same shape.
        assertion =
          cfg.smtp.passwordSecretRef == null
          || (config.age.secrets ? ${cfg.smtp.passwordSecretRef});
        message = ''
          hwc.business.leads.smtp.passwordSecretRef =
          "${toString cfg.smtp.passwordSecretRef}" but no matching
          agenix secret is declared. Set to null to disable customer
          email entirely.
        '';
      }
    ];
  };
}
