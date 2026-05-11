# domains/business/datax/default.nix
#
# DataX — Facebook group monitoring database and merge pipeline
#
# NAMESPACE: hwc.business.datax.*
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (PostgreSQL engine)
#
# USED BY:
#   - domains/business/index.nix
#   - Manual: fb-merge <export.json>
#   - Manual: fb-scrape <group-url> -n 50
#   - Automated: systemd timer fb-scrape.timer

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.datax;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    psycopg2
  ]);

  mergeScript = pkgs.writeShellApplication {
    name = "fb-merge";
    runtimeInputs = [ pythonEnv ];
    text = ''
      exec python ${./fb-monitor-bak/merge.py} "$@"
    '';
  };
in
{
  imports = [
    ./database.nix
  ];

  # OPTIONS
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
      description = "PostgreSQL user for datax database";
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
        description = "Number of posts to collect per scrape run";
      };

      depth = lib.mkOption {
        type = lib.types.enum [ "posts" "comments" ];
        default = "posts";
        description = "Scrape depth: 'posts' (fast) or 'comments' (full threads)";
      };

      timerInterval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 06,12,18,00:00:00";
        description = "systemd calendar expression for scrape schedule";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/datax/fb-scraper";
        description = "Persistent data directory (session.json, exports)";
      };

      containerImage = lib.mkOption {
        type = lib.types.str;
        default = "localhost/fb-group-scraper:latest";
        description = "Podman image name for the scraper";
      };
    };

    fbClassifier = {
      enable = lib.mkEnableOption "FB post classifier (Claude CLI + Discord notifications)";

      claudeBin = lib.mkOption {
        type = lib.types.str;
        default = "/etc/profiles/per-user/eric/bin/claude";
        description = "Path to Claude Code CLI binary";
      };

      limit = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Max unclassified posts to process per run";
      };

      timerInterval = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 07,13,19,01:00:00";
        description = "systemd calendar expression for classify schedule (1h after each scrape)";
      };

      discordWebhookSecret = lib.mkOption {
        type = lib.types.str;
        default = "datax-discord-webhook";
        description = "Name of the agenix secret containing the Discord webhook URL";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (
    let
      fb-classify-script = pkgs.writeShellApplication {
        name = "fb-classify";
        runtimeInputs = [ pythonEnv ];
        text = ''
          exec python ${./fb-classifier/classify.py} "$@"
        '';
      };

      fb-scrape-script = pkgs.writeShellApplication {
        name = "fb-scrape";
        runtimeInputs = [ pkgs.podman ];
        text = ''
          exec podman run --rm \
            --network=host \
            -v "${cfg.fbScraper.dataDir}:/data:Z" \
            -e "PLAYWRIGHT_BROWSERS_PATH=/ms-playwright" \
            ${cfg.fbScraper.containerImage} \
            --profile /data/browser-profile \
            "$@"
        '';
      };

      groupArgs = lib.concatStringsSep " " cfg.fbScraper.groups;

      fb-scrape-run = pkgs.writeShellApplication {
        name = "fb-scrape-run";
        runtimeInputs = [ pkgs.podman pkgs.findutils mergeScript ];
        excludeShellChecks = [ "SC2043" ]; # loop intentionally runs once per group URL
        text = ''
          set -euo pipefail
          TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
          EXPORT_DIR="${cfg.fbScraper.dataDir}/exports"

          for GROUP_URL in ${groupArgs}; do
            SLUG=$(echo "$GROUP_URL" | grep -oP 'groups/\K[^/]+')
            OUTFILE="$EXPORT_DIR/''${SLUG}_''${TIMESTAMP}.json"

            echo "[fb-scrape-run] Scraping $GROUP_URL → $OUTFILE"

            podman run --rm \
              --network=host \
              -v "${cfg.fbScraper.dataDir}:/data:Z" \
              -e "PLAYWRIGHT_BROWSERS_PATH=/ms-playwright" \
              ${cfg.fbScraper.containerImage} \
              --profile /data/browser-profile \
              -n ${toString cfg.fbScraper.postsPerRun} \
              -d ${cfg.fbScraper.depth} \
              -o "/data/exports/''${SLUG}_''${TIMESTAMP}.json" \
              -q \
              "$GROUP_URL" || {
                echo "[fb-scrape-run] ERROR: scrape failed for $GROUP_URL" >&2
                continue
              }

            echo "[fb-scrape-run] Merging $OUTFILE → Postgres"
            fb-merge "$OUTFILE" || echo "[fb-scrape-run] ERROR: merge failed for $OUTFILE" >&2
          done

          # Clean up exports older than 7 days
          find "$EXPORT_DIR" -name '*.json' -mtime +7 -delete 2>/dev/null || true

          echo "[fb-scrape-run] Done."
        '';
      };
    in {
      # fb-merge always available; scraper/classifier scripts only when enabled
      environment.systemPackages = [ mergeScript ]
        ++ lib.optionals cfg.fbScraper.enable [ fb-scrape-script fb-scrape-run ]
        ++ lib.optionals cfg.fbClassifier.enable [ fb-classify-script ];

      systemd.tmpfiles.rules = lib.mkIf cfg.fbScraper.enable [
        "d ${cfg.fbScraper.dataDir} 0755 eric users -"
        "d ${cfg.fbScraper.dataDir}/exports 0755 eric users -"
      ];

      systemd.services.fb-scrape = lib.mkIf cfg.fbScraper.enable {
        description = "FB group scraper";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
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
          CLAUDE_BIN = cfg.fbClassifier.claudeBin;
          PROMPT_FILE = "${./fb-classifier/prompt.txt}";
          DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.fbClassifier.discordWebhookSecret}.path;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
          ExecStart = "${fb-classify-script}/bin/fb-classify --limit ${toString cfg.fbClassifier.limit}";
          TimeoutStartSec = "10min";
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
