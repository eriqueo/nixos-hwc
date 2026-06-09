# domains/server/native/ai/market-intelligence/options.nix
#
# Market Intelligence System — construction-sector earnings research.
# Namespace: hwc.server.ai.marketIntelligence (the `native/` segment is grouping-only).
#
# A standalone Python app (code in dataDir, like hermes-agent/scripts) that
# monitors 12 public companies, runs DeepSeek V4 analysis on earnings, grades
# the resulting directional signals deterministically, and serves a static
# dashboard. It shares the hermes DeepSeek endpoint/key but is otherwise
# independent of the hermes agent and the market-trials dashboard.
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.ai.marketIntelligence = {
    enable = lib.mkEnableOption "Market Intelligence system (earnings signals + static dashboard)";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/market-intelligence";
      description = ''
        Application root: holds the Python package tree (jobs/, ingest/,
        analysis/, ledger/, grading/, dashboard/), config/, the SQLite DB under
        data/, logs/, and dashboard/data.json. Owned by eric:users.
      '';
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 25445;
      description = "External Caddy HTTPS port for the intelligence dashboard (market-trials is 25444).";
    };

    dailyCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Mon-Fri 15:00";
      description = ''
        systemd OnCalendar for the daily cycle. Host timezone is America/Denver,
        so this is 15:00 MT on weekdays (after US market close).
      '';
    };

    weeklyCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Fri 16:00";
      description = "systemd OnCalendar for the weekly cycle (daily + macro panel + digest). 16:00 MT Fridays.";
    };

    fredKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "market-intelligence-fred-key";
      description = "agenix secret NAME for the FRED API key (-> MARKET_INTEL_FRED_KEY).";
    };

    fmpKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "market-intelligence-fmp-key";
      description = "agenix secret NAME for the FMP API key (-> MARKET_INTEL_FMP_KEY).";
    };

    deepseekKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "hermes-deepseek-key";
      description = ''
        agenix secret NAME for the DeepSeek API key (-> DEEPSEEK_API_KEY).
        Reused from the hermes module, which declares and mounts it — hence the
        hwc.server.ai.hermes.enable assertion below.
      '';
    };

    discordWebhookSecret = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "market-intelligence-discord-webhook";
      description = ''
        agenix secret NAME for a Discord webhook (-> MARKET_INTEL_DISCORD_WEBHOOK).
        Empty disables notifications (the jobs log a summary instead). If set,
        also declare the matching age.secret and secrets.nix rule.
      '';
    };
  };
}
