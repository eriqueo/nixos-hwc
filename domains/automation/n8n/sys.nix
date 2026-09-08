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

    ${lib.optionalString (cfg.secrets.discordWebhookUrlFile != null) ''
      echo "DISCORD_WEBHOOK_URL=$(cat ${cfg.secrets.discordWebhookUrlFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.discordWebhookFrigateFile != null) ''
      echo "DISCORD_WEBHOOK_FRIGATE_URL=$(cat ${cfg.secrets.discordWebhookFrigateFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.anthropicApiKeyFile != null) ''
      echo "ANTHROPIC_API_KEY=$(cat ${cfg.secrets.anthropicApiKeyFile})" >> ${secretsEnvFile}
    ''}

    ${lib.optionalString (cfg.secrets.hwcLeadsHmacFile != null) ''
      echo "HWC_LEADS_HMAC_SECRET=$(cat ${cfg.secrets.hwcLeadsHmacFile})" >> ${secretsEnvFile}
    ''}

  '';

  # Every secret this unit feeds into the container, in one list. The env-file
  # generator above and hasSecrets below both derive from it, so adding a
  # secret cannot leave one of the two behind.
  secretFiles = lib.filter (p: p != null) [
    cfg.secrets.estimatorApiKeyFile
    cfg.secrets.jobtreadGrantKeyFile
    cfg.secrets.discordWebhookUrlFile
    cfg.secrets.discordWebhookFrigateFile
    cfg.secrets.anthropicApiKeyFile
    cfg.secrets.hwcLeadsHmacFile
  ];

  # Check if any secrets are configured
  hasSecrets = secretFiles != [];

  # Rotation triggers. The options above carry mount PATHS (/run/agenix/<name>),
  # not secret names, so the encrypted source is recovered by matching a mount
  # back to its declaration. `.file` is the .age path; changing the encrypted
  # content changes it, which is what makes the trigger fire. A path with no
  # matching declaration contributes nothing rather than failing evaluation —
  # the machine may legitimately point an option at a non-agenix file.
  ageFileFor = p:
    let matches = lib.filter (s: toString s.path == toString p)
                    (lib.attrValues (config.age.secrets or {}));
    in if matches == [] then null else (lib.head matches).file;

  # encryption.keyFile rides along: it is passed to the container as an
  # environmentFile too, and podman re-reads env files only at unit start.
  secretAgeFiles = lib.filter (f: f != null) (map ageFileFor
    (secretFiles ++ lib.optional (cfg.encryption.keyFile != null) cfg.encryption.keyFile));
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
        N8N_HOST = "hwc-server.ocelot-wahoo.ts.net";
        GENERIC_TIMEZONE = cfg.timezone;
        N8N_PERSONALIZATION_ENABLED = "false";
        N8N_VERSION_NOTIFICATIONS_ENABLED = "false";
        N8N_DIAGNOSTICS_ENABLED = "false";
        N8N_HIRING_BANNER_ENABLED = "false";
        N8N_EDITOR_BASE_URL = "https://hwc-server.ocelot-wahoo.ts.net:10000/";
        WEBHOOK_URL = "https://hwc-server.ocelot-wahoo.ts.net:10000/";
        N8N_PROXY_HOPS = "1";
        N8N_ENDPOINT_WEBHOOK = "webhook";
        N8N_ENDPOINT_REST = "rest";
        DB_TYPE = "sqlite";
        DB_SQLITE_DATABASE = "/home/node/.n8n/database.sqlite";
        # Allow file access to /data for scraper CSV imports (semicolon-separated)
        N8N_RESTRICT_FILE_ACCESS_TO = "/home/node/.n8n-files;/data";
        # Allow access to environment variables in code nodes (required for $env.JOBTREAD_GRANT_KEY etc.)
        N8N_BLOCK_ENV_ACCESS_IN_NODE = "false";
        # Allow `require("crypto")` in Code nodes — needed by the
        # work_calculator_lead thin shell to HMAC-sign POST /leads.
        NODE_FUNCTION_ALLOW_BUILTIN = "crypto";
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
      systemd.services.podman-n8n.serviceConfig.ExecStartPre = [ "${generateSecretsEnv}" ];
    })

    # Rotation. Gated on the TRIGGER list, not on hasSecrets: encryption.keyFile
    # is an environmentFile too and can be set with no `secrets.*` at all, and
    # podman re-reads env files only at unit start.
    #
    # The env file is written by ExecStartPre, i.e. only when the unit restarts.
    # `nixos-rebuild switch` re-mounts /run/agenix/<name> but leaves podman-n8n
    # running, so a rotated secret kept serving the OLD bytes until someone
    # remembered `systemctl restart podman-n8n` — the footgun documented at
    # domains/business/leads/index.nix (hmacSecretRef). Same mechanism
    # hwc-notify and hwc-leads use for their own secrets.
    (lib.mkIf (secretAgeFiles != []) {
      systemd.services.podman-n8n.restartTriggers = secretAgeFiles;
    })
  ]);
}
