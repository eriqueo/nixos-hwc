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
  groupArgs = lib.concatStringsSep " " cfg.fbScraper.groups;
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
      description = ''
        Path to the market_research project directory.
        Must have npm install already run.
        Container image must be pre-built:
          cd $projectDir && podman build -t market_research .
      '';
    };

    fbScraper = {
      enable = lib.mkEnableOption "FB group scraper (Podman + systemd timer)";

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "https://www.facebook.com/groups/jobtreadpros" ];
        description = "Facebook group URLs to scrape";
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
        description = "Podman image. Build: cd \$projectDir && podman build -t market_research .";
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

      # Scrape one or more groups, then merge each export into Postgres.
      # Runs as eric so rootless Podman + peer DB auth work.
      fb-scrape-run = pkgs.writeShellApplication {
        name = "fb-scrape-run";
        runtimeInputs = [ pkgs.podman pkgs.nodejs pkgs.findutils ];
        excludeShellChecks = [ "SC2086" "SC2043" ];  # SC2086: word split for SELECTORS_MOUNT; SC2043: single-group loop is valid
        text = ''
          set -euo pipefail
          TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
          EXPORT_DIR="${cfg.fbScraper.dataDir}/exports"

          for GROUP_URL in ${groupArgs}; do
            # Extract slug: "https://www.facebook.com/groups/jobtreadpros" → "jobtreadpros"
            SLUG=$(echo "''${GROUP_URL}" | sed 's|.*/groups/||; s|/.*||')
            OUTFILE="''${EXPORT_DIR}/''${SLUG}_''${TIMESTAMP}.json"

            echo "[fb-scrape-run] Scraping ''${GROUP_URL} → ''${OUTFILE}"

            # Mount calibrated selectors if present (falls back to built-in defaults if not)
            SELECTORS_MOUNT=""
            if [ -f "${cfg.projectDir}/config/selectors.json" ]; then
              SELECTORS_MOUNT="-v ${cfg.projectDir}/config/selectors.json:/app/config/selectors.json:ro"
            fi

            podman run --rm \
              --network=host \
              -v "${cfg.fbScraper.dataDir}:/app/data:Z" \
              $SELECTORS_MOUNT \
              "${cfg.fbScraper.containerImage}" \
              "''${GROUP_URL}" \
              -n ${toString cfg.fbScraper.postsPerRun} \
              -d ${cfg.fbScraper.depth} \
              -o "/app/data/exports/''${SLUG}_''${TIMESTAMP}.json" \
              -q \
              || { echo "[fb-scrape-run] ERROR: scrape failed for ''${GROUP_URL}" >&2; continue; }

            echo "[fb-scrape-run] Merging ''${OUTFILE}"
            DATABASE_URL="${databaseUrl}" \
              node ${cfg.projectDir}/bin/merge.mjs "''${OUTFILE}" \
              || echo "[fb-scrape-run] WARN: merge failed for ''${OUTFILE}" >&2
          done

          # Prune exports older than 7 days
          find "''${EXPORT_DIR}" -name '*.json' -mtime +7 -delete 2>/dev/null || true
          echo "[fb-scrape-run] Done."
        '';
      };

      # Classify unclassified posts via LLM adapter, notify Discord for high-signal hits.
      fb-classify-run = pkgs.writeShellApplication {
        name = "fb-classify-run";
        runtimeInputs = [ pkgs.nodejs ];
        text = ''
          exec node ${cfg.projectDir}/bin/classify.mjs --limit ${toString cfg.fbClassifier.limit}
        '';
      };
    in {

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
        description = "FB post classifier";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DATABASE_URL      = databaseUrl;
          DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.fbClassifier.discordWebhookSecret}.path;
          PROMPT_FILE       = "${cfg.fbClassifier.promptFile}";
          CLASSIFIER_ADAPTER = "cli";
          LLM_BIN           = cfg.fbClassifier.claudeBin;
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
