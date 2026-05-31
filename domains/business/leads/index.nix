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
    npmDepsHash = "sha256-dYIkJUt5UbGyYUYyuzFE/+Rtls8AQPLnCAmynZWzDFQ=";

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
  imports = [ ./options.nix ];

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
      ];

      environment = {
        HWC_LEADS_BIND_ADDR           = cfg.bindAddr;
        HWC_LEADS_PORT                = toString cfg.port;
        HWC_LEADS_STATE_DIR           = cfg.statePath;
        HWC_LEADS_LOG_LEVEL           = cfg.logLevel;
        HWC_LEADS_NOTIFY_URL          = cfg.notifyServiceUrl;
        HWC_LEADS_PG_DSN              = cfg.postgresDsn;
        HWC_LEADS_JT_MAPPINGS_FILE    = "${jtMappingsFile}";
      } // lib.optionalAttrs (cfg.hmacSecretRef != null) {
        HWC_LEADS_HMAC_FILE = config.age.secrets.${cfg.hmacSecretRef}.path;
      } // lib.optionalAttrs (cfg.jtGrantKeyRef != null) {
        HWC_LEADS_JT_GRANT_FILE = config.age.secrets.${cfg.jtGrantKeyRef}.path;
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
      mode = "port";
      port = cfg.reverseProxyPort;
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
    ];
  };
}
