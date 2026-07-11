# domains/server/native/ai/market-intelligence/index.nix
#
# Market Intelligence — static dashboard (Caddy file_server) + daily/weekly
# systemd timers running the Python jobs. Mirrors the hermes marketDashboard
# pattern for serving, and runs as eric:users (who is in the `secrets` group,
# so the job wrappers read /run/agenix directly — no plaintext env file).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.marketIntelligence;
  paths = config.hwc.paths;

  # Declarative interpreter: yfinance from nixpkgs, everything else stdlib.
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ yfinance ]);

  # Wrapper for one `jobs.run` subcommand. Runs as eric; exports the API keys
  # from /run/agenix at runtime ($(cat) strips the trailing newline) so no
  # secret is ever written to disk or the Nix store.
  runScript = subcommand: pkgs.writeShellScript "market-intelligence-${subcommand}" ''
    set -euo pipefail
    export DEEPSEEK_API_KEY="$(cat /run/agenix/${cfg.deepseekKeySecret})"
    export MARKET_INTEL_ALPHAVANTAGE_KEY="$(cat /run/agenix/${cfg.alphavantageKeySecret})"
    export MARKET_INTEL_FRED_KEY="$(cat /run/agenix/${cfg.fredKeySecret})"
    ${lib.optionalString (cfg.discordWebhookSecret != "") ''
      export MARKET_INTEL_DISCORD_WEBHOOK="$(cat /run/agenix/${cfg.discordWebhookSecret})"
    ''}
    cd ${cfg.dataDir}
    exec ${pythonEnv}/bin/python3 -m jobs.run ${subcommand}
  '';

  mkJobService = subcommand: description: {
    inherit description;
    # agenix runs as an activation script (no agenix.service unit), so secrets
    # in /run/agenix are already present by the time these timer-driven units
    # fire — no ordering dependency needed beyond the network.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = lib.mkForce "eric";
      Group = "users";
      WorkingDirectory = cfg.dataDir;
      ExecStart = "${runScript subcommand}";
    };
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
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

    alphavantageKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "market-intelligence-alphavantage-key";
      description = "agenix secret NAME for the Alpha Vantage API key (-> MARKET_INTEL_ALPHAVANTAGE_KEY). Source of earnings transcripts + beat/miss.";
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

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [

    # ── Static dashboard (Caddy file_server over the tailnet) ───────────────
    {
      hwc.networking.shared.routes = [{
        name = "market-intelligence";
        mode = "vhost";
        root = "${cfg.dataDir}/dashboard";
      }];

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 eric users - -"
        "d ${cfg.dataDir}/dashboard 0750 eric users - -"
        "d ${cfg.dataDir}/data 0750 eric users - -"
        "d ${cfg.dataDir}/logs 0750 eric users - -"
      ];
    }

    # ── agenix secrets ──────────────────────────────────────────────────────
    # The FRED/FMP keys are declared in domains/secrets/declarations/services.nix
    # (the repo's canonical secret-declaration layer, populated by the `secret`
    # tool); the DeepSeek key is declared by the hermes module. This module only
    # consumes them at runtime from /run/agenix, so it declares no age.secrets
    # itself (avoids duplicate definitions / multiple writers).

    # ── Daily / weekly jobs + timers ────────────────────────────────────────
    {
      systemd.services.market-intelligence-daily =
        mkJobService "daily" "Market Intelligence — daily cycle (prices, earnings, grading, dashboard)";
      systemd.services.market-intelligence-weekly =
        mkJobService "weekly" "Market Intelligence — weekly cycle (daily + macro panel + digest)";

      systemd.timers.market-intelligence-daily = {
        description = "Market Intelligence daily (15:00 MT weekdays)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.dailyCalendar;
          Persistent = true;
        };
      };
      systemd.timers.market-intelligence-weekly = {
        description = "Market Intelligence weekly (16:00 MT Fridays)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.weeklyCalendar;
          Persistent = true;
        };
      };
    }

    #==========================================================================
    # VALIDATION
    #==========================================================================
    {
      assertions = [
        {
          assertion = config.hwc.server.ai.hermes.enable;
          message = ''
            hwc.server.ai.marketIntelligence reuses the hermes DeepSeek key
            (${cfg.deepseekKeySecret}), which only mounts when
            hwc.server.ai.hermes is enabled. Enable hermes, or point
            deepseekKeySecret at a key this module declares.
          '';
        }
        {
          assertion = builtins.pathExists ../../../../secrets/parts/services/market-intelligence-fred-key.age;
          message = "market-intelligence-fred-key.age is missing — run: cd ~/.nixos && sudo agenix -e domains/secrets/parts/services/market-intelligence-fred-key.age";
        }
        {
          assertion = builtins.pathExists ../../../../secrets/parts/services/market-intelligence-alphavantage-key.age;
          message = "market-intelligence-alphavantage-key.age is missing — add it via the `secret` TUI (category: services).";
        }
      ];
    }
  ]);
}
