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

  # One producer for the database name (research-scout precedent). Renamed from
  # `datax` on 2026-08-26: the scraper was built under a project called datax in
  # 2026-05 and the database kept that birth name for three months. It holds
  # fb_posts, fb_comments, post_classifications and scrape_sources — lead-scout
  # tables, all of them, and no DataX table. Do not confuse it with
  # `datax_monitor`, which IS DataX monitoring and is a different database
  # (domains/business/datax-monitor).
  dbName = "lead_scout";

  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.workspaceRoot}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";
  claudeModel = "opus";

  chromiumBin = "${pkgs.chromium}/bin/chromium";

  botTokenFile = "/run/agenix/${cfg.discordApprovals.botTokenSecret}";

  # Discord is a control plane for explicit human approval, not a dependency
  # of the HTTP/MCP server. The main unit only needs this environment to author
  # review cards; the separate gateway unit owns buttons and modals. Keeping the
  # shared protocol in one attrset prevents sender/consumer configuration drift.
  discordApprovalEnvironment = lib.optionalAttrs cfg.discordApprovals.enable {
    DISCORD_BOT_TOKEN_FILE = botTokenFile;
    DISCORD_APPROVAL_GUILD_ID = cfg.discordApprovals.guildId;
    DISCORD_APPROVAL_CHANNEL_ID = cfg.discordApprovals.channelId;
    DISCORD_APPROVAL_ALLOWED_USER_ID = cfg.discordApprovals.allowedUserId;
  };

  # systemd restart delays are deterministic. Add 0–5 seconds at the
  # composition root so concurrent Discord recovery does not create a thundering
  # herd; the unit's start-limit below remains the hard retry ceiling.
  discordRestartJitter = pkgs.writeShellScript "lead-scout-discord-approval-restart-jitter" ''
    exec ${pkgs.coreutils}/bin/sleep "$((RANDOM % 6))"
  '';
  # The old inline `lead-scout-deploy` command (pull + npm install + frontend
  # build + restart) is retired: it predated the standard `deploy` dispatcher
  # and its per-repo layout assumptions are wrong for the scout monorepo.
  # Deploys go through ~/600_apps/scout/deploy.sh (`deploy scout`).
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

    workspaceRoot = lib.mkOption {
      type = lib.types.path;
      default = cfg.projectDir;
      description = ''
        Root whose node_modules carries hoisted tooling (tsx). Equal to
        projectDir for a standalone checkout; the monorepo root when
        projectDir is an app inside the scout workspace.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://${dbName}@localhost/${dbName}";
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

    discordApprovals = {
      enable = lib.mkEnableOption "Discord approval controls for DataX reply evaluations";

      botTokenSecret = lib.mkOption {
        type = lib.types.str;
        default = "hermes-discord-bot-token";
        description = ''
          agenix secret NAME containing the Discord bot token. The application
          reads it through DISCORD_BOT_TOKEN_FILE; the token never enters the
          Nix store or a systemd environment value.
        '';
      };

      guildId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Only this Discord guild may issue reply-review actions.";
      };

      channelId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Discord channel where interactive reply-review cards are sent.";
      };

      allowedUserId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Only this Discord user may approve, edit, skip, or give feedback.";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    #--------------------------------------------------------------------------
    # Database on the shared Postgres instance
    #--------------------------------------------------------------------------
    # Moved here on 2026-08-26 from domains/business/datax/{index,database}.nix,
    # which was deleted. That module's name violated Law 2: after the database
    # rename it owned nothing called datax. home-scout and research-scout each
    # declare their own database inline; lead-scout now does the same.
    #
    # ensureDBOwnership runs `ALTER DATABASE lead_scout OWNER TO lead_scout` on
    # every postgresql start. lead_scout was owned by `postgres` (the other two
    # scout databases are owned by their own role), so this DOES change live
    # state once. Verified safe before writing it: all 18 tables and every
    # sequence in lead_scout.public are ALREADY owned by the lead_scout role,
    # so no object ownership moves and no privilege is withdrawn — `postgres`
    # is a superuser and keeps full access, and `eric` (also superuser, the
    # role hwc.business.crm's read-only ingest connects as) is unaffected.
    # What the role GAINS is schema public's UC via pg_database_owner, which is
    # how home_scout and research_scout get CREATE for their app migrations.
    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [{
        name = dbName;
        ensureDBOwnership = true;
      }];
    };

    # NO postStart grant — the `GRANT ${dbName} TO eric` line here was dead
    # (`$PSQL` undefined, `|| true` swallowing it) and unnecessary (trust auth
    # plus a superuser `eric`). Removed 2026-08-28; see
    # domains/data/databases/README.md.

    # The old module's six raw GRANT/ALTER DEFAULT PRIVILEGES statements are
    # deliberately NOT carried over. They were written when the role did not own
    # the objects; it does now, and an owner's privileges are implicit. Checked
    # against the live cluster: the only relacl entries are self-grants
    # (`lead_scout=arwdDxt/lead_scout`), pg_default_acl is empty, and the one
    # substantive grant — CREATE on schema public — is what ensureDBOwnership
    # supplies above. Nothing the app queries depends on them.
    #
    # The old module's `$PSQL -f fb-monitor-bak/schema.sql` is also NOT carried
    # over. That file is the original 2026-05 three-table fb-monitor schema
    # (fb_posts/fb_comments/fb_capture_log, all CREATE TABLE IF NOT EXISTS). The
    # app owns its schema now via ~/600_apps/scout/apps/lead-scout/src/db/
    # migrations and the live `_migrations` table; the database has 18 tables
    # and the file's columns are stale. It is a no-op today and a hazard on a
    # rebuilt cluster, where it would seed a wrong fb_posts ahead of migration 1.

    # NO per-database backup registration, matching home-scout and
    # research-scout.
    #
    # This block was written to KEEP the registration, reasoning that dropping
    # it would silently retire a running backup. That reasoning was correct when
    # written and went stale within the hour: postgresql-db-backup was retired
    # wholesale later the same day (machines/server/config.nix,
    # `backup.perDatabase.enable = false`) because it wrote to
    # /home/eric/backups/postgres, a path in no borg source. A registration into
    # a disabled option is dead config that reads as a backup, so it is removed
    # rather than left to mislead.
    #
    # lead_scout IS backed up, by the mechanism that covers every database: the
    # borg pre-hook's nightly `pg_dumpall` into /var/lib/backups, which borg
    # carries. Verify there — `zcat /var/lib/backups/postgresql-<date>.sql.gz |
    # rg '^CREATE DATABASE'` — not in postgresql-db-backup.

    # Chromium kept on global PATH so interactive `npm run scrape` from a user
    # shell can find it; the service itself uses PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH.
    environment.systemPackages = [ pkgs.chromium ];

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
      } // discordApprovalEnvironment // lib.optionalAttrs (cfg.channelMap != { }) {
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
        CLAUDE_MODEL = claudeModel;

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

        # Backstop for the app's own 10s SIGTERM drain; deliberately NOT
        # SuccessExitStatus=143. Rationale in domains/server/README.md
        # (2026-08-15) — it governs all three scouts, so it lives one layer up.
        TimeoutStopSec   = "30s";

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

    # Discord Gateway sidecar. It can fail or exhaust its bounded restart budget
    # without affecting lead-scout.service, while still sharing the app's DB and
    # browser profile for explicitly approved Facebook comments.
    systemd.services.lead-scout-discord-approvals = lib.mkIf cfg.discordApprovals.enable {
      description = "Lead Scout Discord reply approval bot";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      # Five failed starts in five minutes leave the unit visibly failed. This
      # sheds reconnect churn during a sustained Discord/configuration outage;
      # an operator or the next deployment can restart it explicitly.
      startLimitIntervalSec = 300;
      startLimitBurst = 5;

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        CLAUDE_MODEL = claudeModel;
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      } // discordApprovalEnvironment;

      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -f ${cli}"
          "${pkgs.coreutils}/bin/test -f ${tsx}"
          "${pkgs.coreutils}/bin/test -r ${botTokenFile}"
          "${pkgs.coreutils}/bin/test -s ${botTokenFile}"
          discordRestartJitter
        ];
        ExecStart = "${node} ${tsx} ${cli} discord:approvals";
        WorkingDirectory = cfg.projectDir;
        User = lib.mkForce cfg.user;
        Group = lib.mkForce "users";
        Restart = "on-failure";
        RestartSec = "15s";

        # The app drains its Gateway client and Postgres pool on SIGTERM. This
        # is a deadline backstop, not a success-status mask.
        TimeoutStopSec = "30s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [
          "${cfg.projectDir}/data"
          "/tmp"
        ];
      };
    };

    # VALIDATION
    assertions = [
      {
        assertion =
          !cfg.discordApprovals.enable
          || builtins.hasAttr cfg.discordApprovals.botTokenSecret config.age.secrets;
        message = "Lead Scout Discord approvals are enabled but their botTokenSecret has no generated agenix mount.";
      }
      {
        assertion = !cfg.discordApprovals.enable || cfg.discordApprovals.guildId != "";
        message = "Lead Scout Discord approvals require discordApprovals.guildId.";
      }
      {
        assertion = !cfg.discordApprovals.enable || cfg.discordApprovals.channelId != "";
        message = "Lead Scout Discord approvals require discordApprovals.channelId.";
      }
      {
        assertion = !cfg.discordApprovals.enable || cfg.discordApprovals.allowedUserId != "";
        message = "Lead Scout Discord approvals require discordApprovals.allowedUserId.";
      }
    ];
  };
}
