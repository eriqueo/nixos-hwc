# domains/automation/n8n/sys.nix
#
# n8n Container Service
# Uses official n8nio/n8n image for simpler updates
{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.automation.n8n;
  paths = config.hwc.paths;

  # Path to generated secrets env file
  secretsEnvFile = "/run/n8n/secrets.env";

  # Script to generate environment file from agenix secrets
  generateSecretsEnv = pkgs.writeShellScript "n8n-generate-secrets-env" ''
    mkdir -p /run/n8n
    rm -f ${secretsEnvFile}
    touch ${secretsEnvFile}
    chmod 600 ${secretsEnvFile}

    ${lib.optionalString (cfg.secrets.estimatorApiKeyFile != null) ''
      echo "ESTIMATOR_API_KEY=$(cat ${cfg.secrets.estimatorApiKeyFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.jobtreadGrantKeyFile != null) ''
      echo "JOBTREAD_GRANT_KEY=$(cat ${cfg.secrets.jobtreadGrantKeyFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.slackWebhookUrlFile != null) ''
      echo "SLACK_WEBHOOK_URL=$(cat ${cfg.secrets.slackWebhookUrlFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.anthropicApiKeyFile != null) ''
      echo "ANTHROPIC_API_KEY=$(cat ${cfg.secrets.anthropicApiKeyFile})" >> ${secretsEnvFile}
    ''}

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (key: path:
      let envName = "GOTIFY_TOKEN_" + lib.toUpper (builtins.replaceStrings ["-"] ["_"] key);
      in ''echo "${envName}=$(cat ${path})" >> ${secretsEnvFile}''
    ) cfg.secrets.gotifyTokenFiles)}
  '';

  # Check if any secrets are configured
  hasSecrets = cfg.secrets.estimatorApiKeyFile != null
            || cfg.secrets.jobtreadGrantKeyFile != null
            || cfg.secrets.slackWebhookUrlFile != null
            || cfg.secrets.anthropicApiKeyFile != null
            || cfg.secrets.gotifyTokenFiles != {};
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "n8n";
      image = cfg.image;
      networkMode = "host";  # Needs host for Tailscale funnel integration
      gpuEnable = false;
      timeZone = cfg.timezone;
      ports = [];  # Host network mode, port is exposed directly
      volumes = [
        "${cfg.dataDir}:/home/node/.n8n"
        "/data:/data"  # Scraper output access
      ];
      environment = {
        N8N_PORT = toString cfg.port;
        N8N_PROTOCOL = "https";
        N8N_HOST = "hwc.ocelot-wahoo.ts.net";
        GENERIC_TIMEZONE = cfg.timezone;
        N8N_PERSONALIZATION_ENABLED = "false";
        N8N_VERSION_NOTIFICATIONS_ENABLED = "false";
        N8N_DIAGNOSTICS_ENABLED = "false";
        N8N_HIRING_BANNER_ENABLED = "false";
        N8N_EDITOR_BASE_URL = "https://hwc.ocelot-wahoo.ts.net:10000/";
        WEBHOOK_URL = "https://hwc.ocelot-wahoo.ts.net:10000/";
        N8N_PROXY_HOPS = "1";
        N8N_ENDPOINT_WEBHOOK = "webhook";
        N8N_ENDPOINT_REST = "rest";
        DB_TYPE = "sqlite";
        DB_SQLITE_DATABASE = "/home/node/.n8n/database.sqlite";
        # Allow file access to /data for scraper CSV imports (semicolon-separated)
        N8N_RESTRICT_FILE_ACCESS_TO = "/home/node/.n8n-files;/data";
        # Allow access to environment variables in code nodes (required for $env.JOBTREAD_GRANT_KEY etc.)
        N8N_BLOCK_ENV_ACCESS_IN_NODE = "false";
      } // cfg.extraEnv;
      environmentFiles =
        (lib.optional (cfg.encryption.keyFile != null) cfg.encryption.keyFile)
        ++ (lib.optional hasSecrets secretsEnvFile);
      memory = "2g";
      cpus = "2.0";
    })

    # Ensure data directory exists
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 1000 1000 -"
        "d /run/n8n 0755 root root -"
      ];
    }

    # Generate secrets env file before container starts
    (lib.mkIf hasSecrets {
      systemd.services.podman-n8n = {
        serviceConfig.ExecStartPre = [ "${generateSecretsEnv}" ];
      };
    })
  ]);
}
