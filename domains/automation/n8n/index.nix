# domains/automation/n8n/index.nix
#
# N8N - Workflow automation platform for alert routing and notifications
# Uses official n8nio/n8n container image
#
# NAMESPACE: hwc.automation.n8n.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#   - Optional: hwc.monitoring.alertmanager (webhook consumer)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.n8n;
  paths = config.hwc.paths;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  workflowPostgres = cfg.workflowPostgresql;
  # TEMPORARY:2.46.1 and2.46.4 retain vulnerable system Brotli/curl.
  # Preserve the app and all other DHI libraries. Remove after an upstream
  # image passes the same library scan and isolated database/key recovery.
  securityApks = [
    { file = "brotli-libs-1.2.1-r0.apk"; sha256 = "62a7e37e43bbfc1f8525a00ad2125fd5897135dc93b849733884cb78ffd8e26c"; }
    { file = "libcurl-8.23.0-r0.apk"; sha256 = "1f70ca404818805a6465b615bbfe84ef861488a963d7e630108ebd7fbaa51665"; }
  ];
  securityRuntime = helpers.mkRuntimeImage {
    name = "n8n";
    version = "2.46.1-brotli1.2.1-curl8.23.0";
    recipe = ''
      FROM docker.io/library/alpine@sha256:c26612752c78b18faacd63c7d50f4592c2e7b0f25e0e20e82bd74e465c57ab0d AS security
      RUN mkdir /packages ${lib.concatMapStrings (apk: '' \
          && wget -q -O /packages/${apk.file} https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/${apk.file} \
          && echo '${apk.sha256}  /packages/${apk.file}' | sha256sum -c -'') securityApks}
      FROM docker.io/n8nio/n8n@sha256:aaab3b3a5a317850d07fca58630bdcf97783f37ba7a7a52792a1b1e594395f11
      USER root
      COPY --from=security /sbin/apk /tmp/apk-security
      COPY --from=security /usr/lib/libapk.so.3.0.0 /tmp/apk-security-lib/libapk.so.3.0.0
      COPY --from=security /etc/apk/keys /tmp/apk-security-keys
      COPY --from=security /packages /tmp/apk-security-packages
      RUN LD_LIBRARY_PATH=/tmp/apk-security-lib /tmp/apk-security --repositories-file /dev/null --keys-dir /tmp/apk-security-keys --no-network add --upgrade /tmp/apk-security-packages/*.apk \
          && rm -rf /tmp/apk-security /tmp/apk-security-lib /tmp/apk-security-keys /tmp/apk-security-packages
      USER node
    '';
  };
in
{
  # OPTIONS
  options.hwc.automation.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation platform";

    image = lib.mkOption {
      type = lib.types.str;
      default = securityRuntime.image;
      description = "n8n container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5678;
      description = "n8n web interface port";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        Editor + webhook base URL, `https://<owner fqdn>:<n8n route port>`,
        derived on every host from hwc.networking.shared.routeOwners.n8n and
        the `n8n` port route (routes.nix). Every caller that pins n8n's
        tailnet address (the *arr media-pipeline webhook, the container's own
        N8N_EDITOR_BASE_URL/WEBHOOK_URL) reads this, so moving n8n is the
        routeOwners entry alone.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/n8n";
      description = "Data directory for n8n workflows and configuration";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Denver";
      description = "Timezone for workflow scheduling";
    };

    encryption = {
      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to encryption key file for credentials (via agenix)";
      };
    };

    workflowPostgresql = {
      credentialIds = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_-]+"); default = [];
        description = "Existing PostgreSQL credential IDs for the shared HWC workflow database. Empty disables managed credential reconciliation; n8n's own state stays SQLite.";
      };
      database = lib.mkOption { type = lib.types.str; default = "hwc"; };
      role = lib.mkOption { type = lib.types.str; default = "n8n"; };
      passwordSecret = lib.mkOption { type = lib.types.str; default = "n8n-postgres-env"; };
      passwordEnvironmentField = lib.mkOption {
        type = lib.types.str; readOnly = true; default = "HWC_POSTGRES_PASSWORD";
        description = "Single field consumed by the OCI environment file, role operator and credential expression.";
      };
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for n8n";
      example = {
        N8N_METRICS = "true";
        N8N_LOG_LEVEL = "info";
      };
    };

    # Secret file paths (via agenix)
    secrets = {
      estimatorApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing ESTIMATOR_API_KEY (via agenix)";
      };

      jobtreadGrantKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing JOBTREAD_GRANT_KEY (via agenix)";
      };

      discordWebhookUrlFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing DISCORD_WEBHOOK_URL (via agenix)";
      };

      discordWebhookFrigateFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to file containing DISCORD_WEBHOOK_FRIGATE_URL (via agenix).
          The camera channel's webhook, consumed by the `home:security:frigate-detect`
          workflow's three direct Discord posts. Those stay direct (rather than
          going through hwc-notify) because the person-detection post is a
          multipart/form-data snapshot upload and hwc-notify's dispatcher takes
          no attachment. Pair with the same agenix entry hwc-notify's
          `discord-frigate` channel consumes (`discord-webhook-frigate`) — one
          secret, two consumers.
        '';
      };

      anthropicApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing ANTHROPIC_API_KEY for Claude workflows (via agenix)";
      };

      hwcLeadsHmacFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to file containing HWC_LEADS_HMAC_SECRET (via agenix).
          Used by the calculator-lead thin-shell workflow to sign the
          forwarded POST /leads request to hwc-leads. Pair with the same
          agenix secret hwc-leads consumes (`hwc-leads-hmac-secret`).
        '';
      };

    };
  };

  #==========================================================================
  # IMPORTS
  #==========================================================================
  imports = [
    ./sys.nix
  ];

  #==========================================================================
  # IMPLEMENTATION (non-container config)
  #==========================================================================
  config = lib.mkMerge [
  {
    hwc.automation.n8n.publicUrl =
      let
        owner = config.hwc.networking.shared.routeOwners.n8n.owner or "main";
        route = lib.findFirst (r: r.name == "n8n") { port = 2443; }
          config.hwc.networking.shared.effectiveRoutes;
      in config.hwc.networking.hosts.url { server = owner; port = route.port; };
  }
  (lib.mkIf cfg.enable {
    # Build/tag this context before activation; the service never substitutes a
    # mutable registry image when its qualified local runtime is absent.
    system.build.n8nRuntimeImageContext = pkgs.runCommand "n8n-runtime-context" {} ''
      mkdir -p "$out"
      ln -s ${securityRuntime.dockerfile} "$out/Dockerfile"
    '';
    # Firewall - localhost + Tailscale
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional (config.networking.interfaces ? "tailscale0") cfg.port;

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions =
      let
        hosts = config.hwc.networking.hosts;
        owner = config.hwc.networking.shared.routeOwners.n8n.owner or "main";
      in [
      {
        assertion = cfg.port != 0;
        message = "n8n port must be configured (hwc.automation.n8n.port)";
      }
      {
        assertion = cfg.dataDir != "";
        message = "n8n data directory must be configured (hwc.automation.n8n.dataDir)";
      }
      {
        assertion = workflowPostgres.credentialIds == [] || (
          config.hwc.data.databases.postgresql.enable
          && config.hwc.secrets.api ? ${workflowPostgres.passwordSecret}
          && builtins.length workflowPostgres.credentialIds <= 16
          && lib.length (lib.unique workflowPostgres.credentialIds) == lib.length workflowPostgres.credentialIds
          && (cfg.extraEnv.N8N_BLOCK_ENV_ACCESS_IN_NODE or "false") == "false");
        message = "Managed n8n PostgreSQL credentials require PostgreSQL, the generated password env file, <=16 unique existing IDs and enabled credential environment expressions";
      }
      # One writer: the host that runs n8n must be the one the route table
      # sends callers to, or webhooks land on a host with no n8n.
      {
        assertion = hosts.self != null && owner == hosts.self;
        message = "hwc.automation.n8n is enabled on ${config.networking.hostName} but "
          + "hwc.networking.shared.routeOwners.n8n names '${owner}' (routes.nix).";
      }
    ];
    # App-owned column policy is the exact union of the ten deployed SQL nodes.
    # Data owns credential/GRANT mechanics; no shared table changes owner.
    hwc.data.databases.postgresql.applicationRoles = lib.optionalAttrs (workflowPostgres.credentialIds != []) {
      ${workflowPostgres.role} = {
        credential.environment = {
          secret = workflowPostgres.passwordSecret;
          field = workflowPostgres.passwordEnvironmentField;
        };
        prepareSql = builtins.readFile ./parts/migrations/004-workflow-run-metadata.sql;
        authority.shared = {
          database = workflowPostgres.database;
          tables = {
            "public.leads" = {
              select = [ "id" "name" "phone_e164" "service_type" "status" "created_at" ];
              update = [ "sms_opted_out" "responded_at" "status" ];
            };
            "public.social_intelligence".select = [ "id" "source" "group_name" "summary" "category" "themes" "sentiment" "marketing_angle" "pain_points" "processed_at" "content_generated" "business_relevance" ];
            "public.webhook_payloads".insert = [ "source" "raw_payload" "received_at" ];
            "public.workflow_runs" = {
              insert = [ "workflow_name" "started_at" "completed_at" "items_processed" "status" "metadata" ];
              select = [ "id" ];
            };
            "public.processing_errors".insert = [ "workflow_name" "node_name" "error_message" "raw_payload" "failed_at" ];
            "public.estimates" = {
              insert = [ "job_number" "job_id" "job_name" "customer_name" "customer_id" "project_type" "total_cost" "total_price" "margin_percent" "labor_hours" "item_count" "project_state" "jt_payload" "pushed_to_jt" "jt_push_error" "jt_push_result" ];
              select = [ "id" ];
            };
          };
        };
      };
    };
  })
  ];
}
