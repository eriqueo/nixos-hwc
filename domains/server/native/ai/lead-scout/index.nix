# domains/server/native/ai/lead-scout/index.nix
#
# Lead Scout — native systemd service
# Long-running HTTP + MCP server on port 8420, proxied externally via
# Cloudflare Tunnel at leads.heartwoodcraft.me.
#
# Scrape/classify scheduling is owned by the in-process cron scheduler
# (src/shells/scheduler.ts) driven by the scrape_sources DB table.
# Per-source schedules are managed via the UI/MCP — no NixOS timers.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.leadScout;
  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.projectDir}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";

  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # One-shot deploy: pull, install deps, build frontend, restart service.
  # Available as `lead-scout-deploy` in PATH on the server.
  lead-scout-deploy = pkgs.writeShellApplication {
    name = "lead-scout-deploy";
    runtimeInputs = [ pkgs.nodejs pkgs.bash pkgs.git pkgs.coreutils pkgs.systemd pkgs.sudo ];
    text = ''
      set -euo pipefail
      PROJECT_DIR="${cfg.projectDir}"

      echo "[deploy] cd ''${PROJECT_DIR}"
      cd "''${PROJECT_DIR}"

      echo "[deploy] git pull --ff-only"
      git pull --ff-only

      echo "[deploy] backend: npm install"
      npm install --silent

      echo "[deploy] frontend: npm install && npm run build"
      pushd frontend >/dev/null
      npm install --silent
      npm run build
      popd >/dev/null

      echo "[deploy] sudo systemctl restart lead-scout"
      sudo systemctl restart lead-scout

      sleep 3
      if systemctl is-active --quiet lead-scout; then
        echo "[deploy] OK -- lead-scout active"
      else
        echo "[deploy] FAILED -- lead-scout did not restart cleanly" >&2
        systemctl status lead-scout --no-pager | head -15 >&2
        exit 1
      fi
    '';
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.ai.leadScout = {
    enable = lib.mkEnableOption "Lead Scout MCP server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8420;
      description = "Port the Lead Scout HTTP/MCP server listens on";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/lead_scout";
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

    channelMap = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { hwc_bozeman_v1 = "discord-webhook-hwc-business"; };
      description = ''
        Per-profile Discord routing: classifier profile id → agenix secret
        NAME of that profile's webhook. Rendered into the app's
        DISCORD_WEBHOOK_FILE_MAP env (JSON of profileId → secret path);
        profiles not listed fall through to discordWebhookSecret.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Chromium kept on global PATH so interactive `npm run scrape` from a user
    # shell can find it; the service itself uses PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH.
    environment.systemPackages = [ lead-scout-deploy pkgs.chromium ];

    # Discord webhook secret (cfg.discordWebhookSecret = "datax-discord-webhook")
    # consumed by the in-process classifier (src/notifications/discord.ts). It is
    # now mounted by the generated secrets layer from
    # parts/services/datax-discord-webhook.age — no inline age.secrets here.

    systemd.services.lead-scout = {
      description = "Lead Scout MCP + HTTP Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DATABASE_URL  = cfg.databaseUrl;
        LOG_LEVEL     = "info";
        NODE_ENV      = "production";
        # Playwright defaults to its bundled chromium under
        # ~/.cache/ms-playwright, which is a generic-Linux dynamic binary
        # NixOS can't load. Point it at the Nix-built chromium.
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.discordWebhookSecret}.path;
      } // lib.optionalAttrs (cfg.channelMap != { }) {
        # Per-profile channel routing (src/notifications/discord.ts
        # resolveWebhookUrl): JSON of profileId → webhook secret path.
        DISCORD_WEBHOOK_FILE_MAP = builtins.toJSON
          (lib.mapAttrs (_: secretName: config.age.secrets.${secretName}.path) cfg.channelMap);
      } // {

        # The classifier shells out to the `claude` CLI. Upstream lead_scout
        # used to hardcode /etc/profiles/per-user/eric/bin/claude as a fallback;
        # it now late-binds via CLAUDE_BIN → `which claude` → candidate paths.
        # This unit's PATH carries only nodejs (no `claude`), so we MUST declare
        # the binary here or classification silently fails to spawn it.
        CLAUDE_BIN = "/etc/profiles/per-user/eric/bin/claude";

        # The server (ExecStart → `serve`) can auto-build the frontend on boot if
        # dist/ is stale, but this unit is hardened (ProtectSystem = "strict";
        # only data/ + /tmp are writable) so a build write to frontend/dist would
        # crash startup. Deploy (lead-scout-deploy) prebuilds the frontend; the
        # service must never try. Hence skip the in-process build entirely.
        SKIP_FRONTEND_BUILD = "1";
      };

      # Needed so detached subprocesses spawned by /api/pipeline tool
      # handlers (mcp/tools.ts) can resolve bare `node` via $PATH.
      path = [ pkgs.nodejs ];

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
  };
}
