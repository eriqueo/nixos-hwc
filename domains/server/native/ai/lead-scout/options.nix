# domains/server/native/ai/lead-scout/options.nix
#
# Lead Scout MCP server options — Facebook group scraper and lead classifier
# served via HTTP on port 8420, proxied via Cloudflare Tunnel.
#
# Per-source scrape/classify scheduling lives in the scrape_sources DB table
# and is driven by the in-process scheduler — no NixOS timer options here.
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
      default = "/home/eric/apps/lead_scout";
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

    discordWebhookSecret = lib.mkOption {
      type = lib.types.str;
      default = "datax-discord-webhook";
      description = ''
        agenix secret NAME containing the Discord webhook URL used by the
        in-process classifier (src/notifications/discord.ts). Legacy filename
        retained (datax-discord-webhook.age) to avoid re-encryption.
      '';
    };
  };
}
