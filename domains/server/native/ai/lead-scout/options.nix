# domains/server/native/ai/lead-scout/options.nix
#
# Lead Scout MCP server options — Facebook group scraper and lead classifier
# served via HTTP on port 8420, proxied via Cloudflare Tunnel.
#
# Includes options for the periodic scrape and classify systemd timers
# (formerly hwc.business.datax.fbScraper / fbClassifier).
{ lib, ... }:
{
  options.hwc.server.ai.leadScout = {
    enable = lib.mkEnableOption "Lead Scout MCP server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8420;
      description = "Port the Lead Scout HTTP/MCP server listens on";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/lead_scout";
      description = "Path to the lead_scout project directory";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://datax@localhost/datax";
      description = "PostgreSQL connection string";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };

    fbScraper = {
      enable = lib.mkEnableOption "Lead Scout FB group scraper (systemd timer)";

      groupIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "jobtread_pros" "secret_bozeman" ];
        description = ''
          Source group IDs to scrape. Each must correspond to a row in the
          scrape_sources table; per-group URL/post-count/depth live there.
        '';
      };

      timerInterval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 06,12,18,00:00:00";
        description = "systemd OnCalendar expression for scrape schedule";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/lead-scout/fb-scraper";
        description = "Persistent state directory (browser profile, JSON exports).";
      };
    };

    fbClassifier = {
      enable = lib.mkEnableOption "Lead Scout post classifier (LLM + Discord)";

      limit = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Max unclassified posts to process per classify run";
      };

      timerInterval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 07,13,19,01:00:00";
        description = "systemd OnCalendar expression (default: 1h after each scrape)";
      };

      discordWebhookSecret = lib.mkOption {
        type = lib.types.str;
        default = "datax-discord-webhook";
        description = ''
          agenix secret NAME containing the Discord webhook URL.
          Legacy filename retained (datax-discord-webhook.age) to avoid re-encryption.
        '';
      };
    };
  };
}
