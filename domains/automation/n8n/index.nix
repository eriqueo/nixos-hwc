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
in
{
  # OPTIONS
  options.hwc.automation.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation platform";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/n8nio/n8n:2.10.3";  # critical tier (Law 15 v12.4): workflow DB — pinned
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
      # One writer: the host that runs n8n must be the one the route table
      # sends callers to, or webhooks land on a host with no n8n.
      {
        assertion = hosts.self != null && owner == hosts.self;
        message = "hwc.automation.n8n is enabled on ${config.networking.hostName} but "
          + "hwc.networking.shared.routeOwners.n8n names '${owner}' (routes.nix).";
      }
    ];
  })
  ];
}
