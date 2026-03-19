# domains/automation/n8n/sys.nix
#
# n8n Container Service
# Uses official n8nio/n8n image for simpler updates
{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.automation.n8n;
  paths = config.hwc.paths;
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
        N8N_EDITOR_BASE_URL = "https://hwc.ocelot-wahoo.ts.net:2443/";
        WEBHOOK_URL = "https://hwc.ocelot-wahoo.ts.net:2443/";
        N8N_ENDPOINT_WEBHOOK = "webhook";
        N8N_ENDPOINT_REST = "rest";
        DB_TYPE = "sqlite";
        DB_SQLITE_DATABASE = "/home/node/.n8n/database.sqlite";
        # SLACK_WEBHOOK_URL loaded via n8n credentials system
        # Allow file access to /data for scraper CSV imports (semicolon-separated)
        N8N_RESTRICT_FILE_ACCESS_TO = "/home/node/.n8n-files;/data";
      } // cfg.extraEnv;
      environmentFiles = lib.optional (cfg.encryption.keyFile != null) cfg.encryption.keyFile;
      memory = "2g";
      cpus = "2.0";
    })

    # Ensure data directory exists
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 1000 1000 -"
      ];
    }
  ]);
}
