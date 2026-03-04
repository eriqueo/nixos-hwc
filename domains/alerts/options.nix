# domains/alerts/options.nix
#
# Alerts Domain - Centralized alert routing to Slack via n8n
#
# NAMESPACE: hwc.alerts.*
#
# DEPENDENCIES:
#   - hwc.automation.n8n (webhook receiver)
#   - hwc.secrets.api.slackWebhookUrlFile (Slack webhook URL)

{ lib, config, ... }:

let
  paths = config.hwc.paths or {};
in
{
  options.hwc.alerts = {
    enable = lib.mkEnableOption "Centralized alert routing to Slack via n8n";

    #==========================================================================
    # WEBHOOK CONFIGURATION
    #==========================================================================
    webhook = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:2443/webhook";
        description = "Base URL for n8n webhook endpoints";
      };

      endpoints = {
        system = lib.mkOption {
          type = lib.types.str;
          default = "system-alerts";
          description = "Webhook endpoint for system alerts (generic)";
        };

        backup = lib.mkOption {
          type = lib.types.str;
          default = "backup-alerts";
          description = "Webhook endpoint for backup notifications";
        };

        smartd = lib.mkOption {
          type = lib.types.str;
          default = "disk-alerts";
          description = "Webhook endpoint for disk/SMART alerts";
        };

        services = lib.mkOption {
          type = lib.types.str;
          default = "service-alerts";
          description = "Webhook endpoint for service failure alerts";
        };
      };
    };

    #==========================================================================
    # ALERT SOURCES
    #==========================================================================
    sources = {
      smartd = {
        enable = lib.mkEnableOption "SMART disk monitoring alerts";
      };

      backup = {
        enable = lib.mkEnableOption "Backup completion/failure alerts";

        onSuccess = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Send alert on successful backup";
        };

        onFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Send alert on backup failure";
        };
      };

      diskSpace = {
        enable = lib.mkEnableOption "Disk space monitoring alerts";

        criticalThreshold = lib.mkOption {
          type = lib.types.int;
          default = 95;
          description = "Critical threshold percentage (P5 alert)";
        };

        warningThreshold = lib.mkOption {
          type = lib.types.int;
          default = 80;
          description = "Warning threshold percentage (P4 alert)";
        };

        filesystems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "/" "/home" "/mnt/media" "/mnt/hot" ];
          description = "Filesystems to monitor for disk space";
        };

        frequency = lib.mkOption {
          type = lib.types.enum [ "hourly" "daily" "every-6h" "every-12h" ];
          default = "hourly";
          description = "How often to check disk space";
        };
      };

      serviceFailures = {
        enable = lib.mkEnableOption "Service failure monitoring alerts";

        services = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            List of services to monitor for failures.
            Empty list = auto-detect critical services.
          '';
          example = [ "podman-immich" "jellyfin" "backup" ];
        };

        # Auto-detected critical services when services list is empty
        autoDetect = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-detect critical services to monitor";
        };
      };
    };

    #==========================================================================
    # SEVERITY MAPPING
    #==========================================================================
    severity = {
      critical = lib.mkOption {
        type = lib.types.str;
        default = "P5";
        description = "Severity tag for critical alerts (immediate action required)";
      };

      warning = lib.mkOption {
        type = lib.types.str;
        default = "P4";
        description = "Severity tag for warning alerts (attention needed)";
      };

      info = lib.mkOption {
        type = lib.types.str;
        default = "P3";
        description = "Severity tag for informational alerts";
      };
    };

    #==========================================================================
    # CLI TOOL
    #==========================================================================
    cli = {
      enable = lib.mkEnableOption "hwc-alert CLI tool for sending alerts";

      defaultEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "system";
        description = "Default webhook endpoint for CLI alerts";
      };

      defaultSeverity = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Default severity for CLI alerts (info, warning, critical)";
      };
    };

    #==========================================================================
    # NTFY SERVER (notification infrastructure)
    #==========================================================================
    server = {
      enable = lib.mkEnableOption "ntfy notification server (container)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "ntfy web port";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state or "/var/lib"}/ntfy";
        description = "Data directory for ntfy server";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "binwiederhier/ntfy:latest";
        description = "ntfy container image";
      };
    };

    #==========================================================================
    # INTERNAL OPTIONS (for cross-domain access)
    #==========================================================================
    _internal = {
      webhookScript = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: webhook sender script package";
      };

      cliScript = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: CLI script package";
      };
    };
  };
}
