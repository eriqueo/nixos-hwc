# domains/server/n8n/options.nix
#
# n8n Workflow Automation Options
# Charter v7.0 compliant

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.server.native.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation platform";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5678;
      description = "n8n web interface port";
    };

    webhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${config.hwc.services.shared.rootHost}";
      defaultText = "https://\${config.hwc.services.shared.rootHost}";
      description = "Base URL for webhook callbacks";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/n8n";
      description = "Data directory for n8n workflows and configuration";
    };
 

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
      description = "Timezone for workflow scheduling";
    };

    encryption = {
      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to encryption key file for credentials (via agenix)";
      };
    };

    database = {
      type = lib.mkOption {
        type = lib.types.enum [ "sqlite" "postgres" ];
        default = "sqlite";
        description = "Database type for n8n";
      };

      sqlite = {
        file = lib.mkOption {
          type = lib.types.path;
          default = "${paths.state}/n8n/database.sqlite";
          description = "SQLite database file path";
        };
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
  };
}
