# domains/business/datax/default.nix
#
# DataX — Facebook group monitoring pipeline
#
# Pipeline: scrape (Podman container) → merge (Node.js) → classify (Node.js + LLM)
#
# External dependency: market_research project at cfg.projectDir
#   Source: https://github.com/eriqueo/market_research
#   One-time setup (on server):
#     cd $projectDir && npm install
#     cd $projectDir && podman build -t market_research .
#     node bin/scrape.mjs --login --headed  (on a machine with display, copy profile to dataDir)
#
# NAMESPACE: hwc.business.datax.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (PostgreSQL engine)
#
# USED BY:
#   - domains/business/index.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.datax;
  chromiumBin = "${pkgs.chromium}/bin/chromium";
in
{
  imports = [ ./database.nix ];

  # ── OPTIONS ────────────────────────────────────────────────────────────────

  options.hwc.business.datax = {
    enable = lib.mkEnableOption "DataX Facebook group monitoring pipeline";

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "datax";
      description = "PostgreSQL database name";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "datax";
      description = "PostgreSQL user";
    };

    projectDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/eric/300_tech/320_projects/market_research";
      description = "Path to the legacy market_research project (deprecated — kept for reference)";
    };

    leadScoutDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/eric/lead_scout";
      description = "Path to the lead_scout project directory (must have npm install run)";
    };

    fbScraper = {
      enable = lib.mkEnableOption "FB group scraper (Podman + systemd timer)";

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "DEPRECATED: Facebook group URLs (use groupIds instead)";
      };

      groupIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "jobtread_pros" "secret_bozeman" ];
        description = "Source group IDs from scrape_sources table";
      };

      postsPerRun = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Posts to collect per scrape run";
      };

      depth = lib.mkOption {
        type = lib.types.enum [ "posts" "comments" ];
        default = "comments";
        description = "'posts' = feed only | 'comments' = expand threads";
      };

      timerInterval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 06,12,18,00:00:00";
        description = "systemd OnCalendar expression for scrape schedule";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/datax/fb-scraper";
        description = "Persistent state: browser profile + JSON exports";
      };

      containerImage = lib.mkOption {
        type = lib.types.str;
        default = "localhost/market_research:latest";
        description = "DEPRECATED: Podman image (lead_scout uses Playwright directly)";
      };
    };

    fbClassifier = {
      enable = lib.mkEnableOption "FB post classifier (LLM + Discord notifications)";

      claudeBin = lib.mkOption {
        type = lib.types.str;
        default = "/etc/profiles/per-user/eric/bin/claude";
        description = "Path to Claude Code CLI binary (used by the cli adapter)";
      };

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
        description = "agenix secret name containing the Discord webhook URL";
      };

      promptFile = lib.mkOption {
        type = lib.types.path;
        default = ./fb-classifier/hwc-bozeman-prompt.txt;
        description = "Path to the LLM classification prompt file";
      };
    };
  };

  # ── IMPLEMENTATION ─────────────────────────────────────────────────────────

  config = lib.mkIf cfg.enable (
    let
      databaseUrl = "postgresql://${cfg.databaseUser}@localhost/${cfg.databaseName}";

      # Scrape all enabled groups via lead_scout CLI.
      # Each group config (URL, post count, depth) lives in scrape_sources DB table.
      fb-scrape-run = pkgs.writeShellApplication {
        name = "fb-scrape-run";
        runtimeInputs = [ pkgs.nodejs ];
        text = ''
          set -euo pipefail
          export DATABASE_URL="${databaseUrl}"
          export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="${chromiumBin}"
          export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true

          cd ${cfg.leadScoutDir}

          for GROUP_ID in ${lib.concatStringsSep " " cfg.fbScraper.groupIds}; do
            echo "[lead_scout] Scraping group: ''${GROUP_ID}"
            npx tsx src/cli.ts scrape --group "''${GROUP_ID}" \
              || { echo "[lead_scout] ERROR: scrape failed for ''${GROUP_ID}" >&2; continue; }
          done

          echo "[lead_scout] Scrape complete."
        '';
      };

      # Classify unclassified posts via lead_scout CLI.
      fb-classify-run = pkgs.writeShellApplication {
        name = "fb-classify-run";
        runtimeInputs = [ pkgs.nodejs ];
        text = ''
          set -euo pipefail
          export DATABASE_URL="${databaseUrl}"

          cd ${cfg.leadScoutDir}

          for GROUP_ID in ${lib.concatStringsSep " " cfg.fbScraper.groupIds}; do
            echo "[lead_scout] Classifying group: ''${GROUP_ID}"
            npx tsx src/cli.ts classify --group "''${GROUP_ID}" --limit ${toString cfg.fbClassifier.limit} \
              || echo "[lead_scout] WARN: classify failed for ''${GROUP_ID}" >&2
          done

          echo "[lead_scout] Classify complete."
        '';
      };
    in {

      # Chromium for Playwright-based scraping (lead_scout CLI)
      environment.systemPackages = lib.mkIf cfg.fbScraper.enable [ pkgs.chromium ];

      # Environment for any process that needs to find chromium
      environment.sessionVariables = lib.mkIf cfg.fbScraper.enable {
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      };

      systemd.tmpfiles.rules = lib.mkIf cfg.fbScraper.enable [
        "d ${cfg.fbScraper.dataDir} 0755 eric users -"
        "d ${cfg.fbScraper.dataDir}/exports 0755 eric users -"
      ];

      # ── Scrape + merge service ──────────────────────────────────────────────

      systemd.services.fb-scrape = lib.mkIf cfg.fbScraper.enable {
        description = "FB group scraper + merge";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
          ExecStart = "${fb-scrape-run}/bin/fb-scrape-run";
          TimeoutStartSec = "30min";
        };
      };

      systemd.timers.fb-scrape = lib.mkIf cfg.fbScraper.enable {
        description = "FB group scraper timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.fbScraper.timerInterval;
          Persistent = true;
          RandomizedDelaySec = "5min";
        };
      };

      # ── Classify service ────────────────────────────────────────────────────

      age.secrets = lib.mkIf cfg.fbClassifier.enable {
        ${cfg.fbClassifier.discordWebhookSecret} = {
          file = ../../secrets/parts/services/datax-discord-webhook.age;
          mode = "0440";
          owner = "eric";
          group = "secrets";
        };
      };

      systemd.services.fb-classify = lib.mkIf cfg.fbClassifier.enable {
        description = "lead_scout post classifier";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DATABASE_URL = databaseUrl;
          DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.fbClassifier.discordWebhookSecret}.path;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
          ExecStart = "${fb-classify-run}/bin/fb-classify-run";
          TimeoutStartSec = "30min";
        };
      };

      systemd.timers.fb-classify = lib.mkIf cfg.fbClassifier.enable {
        description = "FB post classifier timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.fbClassifier.timerInterval;
          Persistent = true;
        };
      };
    }
  );
}
