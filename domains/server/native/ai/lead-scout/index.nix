# domains/server/native/ai/lead-scout/index.nix
#
# Lead Scout — native systemd service
# Serves a Facebook group lead scraper and classifier as an HTTP + MCP server
# on port 8420, proxied externally via Cloudflare Tunnel at leads.heartwoodcraft.me.
#
# Also owns the periodic scrape/classify systemd timers and the Discord
# webhook secret (migrated from hwc.business.datax in 2026-05).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.leadScout;
  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.projectDir}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";

  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # Scrape all configured groups via the lead_scout CLI. The wrapper provides
  # bash in PATH so npm's internal `spawn sh` lifecycle hooks resolve correctly.
  fb-scrape-run = pkgs.writeShellApplication {
    name = "lead-scout-scrape-run";
    runtimeInputs = [ pkgs.nodejs pkgs.bash ];
    text = ''
      set -euo pipefail
      export DATABASE_URL="${cfg.databaseUrl}"
      export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="${chromiumBin}"
      export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true

      cd ${cfg.projectDir}

      for GROUP_ID in ${lib.concatStringsSep " " cfg.fbScraper.groupIds}; do
        echo "[lead_scout] Scraping group: ''${GROUP_ID}"
        npx tsx src/cli.ts scrape --group "''${GROUP_ID}" \
          || { echo "[lead_scout] ERROR: scrape failed for ''${GROUP_ID}" >&2; continue; }
      done

      echo "[lead_scout] Scrape complete."
    '';
  };

  fb-classify-run = pkgs.writeShellApplication {
    name = "lead-scout-classify-run";
    runtimeInputs = [ pkgs.nodejs pkgs.bash ];
    text = ''
      set -euo pipefail
      export DATABASE_URL="${cfg.databaseUrl}"

      cd ${cfg.projectDir}

      for GROUP_ID in ${lib.concatStringsSep " " cfg.fbScraper.groupIds}; do
        echo "[lead_scout] Classifying group: ''${GROUP_ID}"
        npx tsx src/cli.ts classify --group "''${GROUP_ID}" --limit ${toString cfg.fbClassifier.limit} \
          || echo "[lead_scout] WARN: classify failed for ''${GROUP_ID}" >&2
      done

      echo "[lead_scout] Classify complete."
    '';
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ ./options.nix ];

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [

    # ── Long-running HTTP/MCP service ─────────────────────────────────────────
    (lib.mkIf cfg.enable {
      systemd.services.lead-scout = {
        description = "Lead Scout MCP + HTTP Server";
        after = [ "network-online.target" "postgresql.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          DATABASE_URL  = cfg.databaseUrl;
          LOG_LEVEL     = "info";
          NODE_ENV      = "production";
        };

        serviceConfig = {
          Type             = "simple";
          ExecStart        = "${node} ${tsx} ${cli} serve --port ${toString cfg.port}";
          WorkingDirectory = cfg.projectDir;
          User             = cfg.user;
          Restart          = "on-failure";
          RestartSec       = "5s";

          # Security hardening
          NoNewPrivileges      = true;
          PrivateTmp           = true;
          ProtectSystem        = "strict";
          ProtectHome          = "read-only";
          ProtectKernelTunables  = true;
          ProtectKernelModules   = true;
          ProtectControlGroups   = true;
          SystemCallArchitectures = "native";
          RestrictNamespaces     = true;
          RestrictRealtime       = true;
          RestrictSUIDSGID       = true;
          LockPersonality        = true;

          # Read/write access needed for browser profile and data
          ReadWritePaths = [
            "${cfg.projectDir}/data"
            "/tmp"
          ];
        };
      };
    })

    # ── Periodic scrape (oneshot + timer) ─────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.fbScraper.enable) {
      environment.systemPackages = [ pkgs.chromium ];

      environment.sessionVariables = {
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.fbScraper.dataDir} 0755 ${cfg.user} users -"
        "d ${cfg.fbScraper.dataDir}/exports 0755 ${cfg.user} users -"
      ];

      systemd.services.lead-scout-scrape = {
        description = "Lead Scout — FB group scraper + merge";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          ExecStart = "${fb-scrape-run}/bin/lead-scout-scrape-run";
          TimeoutStartSec = "30min";
        };
      };

      systemd.timers.lead-scout-scrape = {
        description = "Lead Scout scrape timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.fbScraper.timerInterval;
          Persistent = true;
          RandomizedDelaySec = "5min";
        };
      };
    })

    # ── Periodic classify (oneshot + timer) + Discord webhook ─────────────────
    (lib.mkIf (cfg.enable && cfg.fbClassifier.enable) {
      age.secrets.${cfg.fbClassifier.discordWebhookSecret} = {
        file = ../../../../secrets/parts/services/datax-discord-webhook.age;
        mode = "0440";
        owner = "root";
        group = "secrets";
      };

      systemd.services.lead-scout-classify = {
        description = "Lead Scout — post classifier + Discord notifier";
        after = [ "postgresql.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DATABASE_URL = cfg.databaseUrl;
          DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.fbClassifier.discordWebhookSecret}.path;
        };
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          ExecStart = "${fb-classify-run}/bin/lead-scout-classify-run";
          TimeoutStartSec = "30min";
        };
      };

      systemd.timers.lead-scout-classify = {
        description = "Lead Scout classify timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.fbClassifier.timerInterval;
          Persistent = true;
        };
      };
    })

    # ── VALIDATION (unconditional — fires even when only sub-features set) ────
    {
      assertions = [
        {
          assertion = cfg.fbScraper.enable -> cfg.enable;
          message = "hwc.server.ai.leadScout.fbScraper.enable requires hwc.server.ai.leadScout.enable.";
        }
        {
          assertion = cfg.fbClassifier.enable -> cfg.enable;
          message = "hwc.server.ai.leadScout.fbClassifier.enable requires hwc.server.ai.leadScout.enable.";
        }
      ];
    }
  ];
}
