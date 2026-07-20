# domains/server/native/ai/research-scout/index.nix
#
# Research Scout — research intelligence pipeline (third scout app).
# Atomic unit is a research item (papers first, arXiv ingester #1).
#
# Two parts:
#   1. research-scout.service — unified HTTP + MCP server on port 8422
#      (classify sweep / digests / trends / budget crons run in-process)
#   2. systemd timer running the Python arXiv ingester daily from
#      <projectDir>/ingest (arXiv announces Mon-Fri ~20:00 ET; weekend
#      runs are cheap no-ops)
#   3. Postgres database `research_scout` on the shared instance
#
# Notifications go to the hwc-notify loopback dispatcher (:11600/notify) —
# no webhook secrets needed (home-scout precedent).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.researchScout;
  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.workspaceRoot}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";

  # arXiv Atom API needs only plain HTTP + stdlib XML.
  ingestPython = pkgs.python3.withPackages (ps: [
    ps.psycopg
    ps.requests
  ]);

  ingestToml = pkgs.writeText "research-scout-ingest.toml" ''
    [arxiv]
    categories = [ ${lib.concatMapStringsSep ", " (c: ''"${c}"'') cfg.arxivCategories} ]
    past_days = 3
    page_size = 200
    request_delay = 3.0
  '';

  ingestEnv = {
    DATABASE_URL = cfg.databaseUrl;
    RESEARCHSCOUT_INGEST_CONFIG = "${ingestToml}";
    PYTHONPATH = "${cfg.projectDir}/ingest";
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.ai.researchScout = {
    enable = lib.mkEnableOption "Research Scout research intelligence pipeline";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8422;
      description = "Port the Research Scout HTTP/MCP server listens on";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/scout/apps/research-scout";
      description = "Path to the research-scout app directory";
    };

    workspaceRoot = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/scout";
      description = ''
        Root whose node_modules carries hoisted tooling (tsx) — the scout
        monorepo root.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://research_scout@localhost/research_scout";
      description = "PostgreSQL connection string";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service and ingest timer as";
    };

    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11600";
      description = "hwc-notify dispatcher base URL (POSTs to /notify)";
    };

    arxivCategories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cs.AI" "cs.CL" "cs.LG" "cs.SE" "cs.MA" "cs.IR" "cs.DB" "stat.ML" ];
      description = ''
        Bootstrap seed for the arXiv category list (G0-calibrated 2026-07-19).
        Insert-only: the DB ingest_sources table owns the live set; curate
        via the Settings UI / research_sources_* tools, not here.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Database on the shared Postgres instance
    services.postgresql = {
      ensureDatabases = [ "research_scout" ];
      ensureUsers = [{
        name = "research_scout";
        ensureDBOwnership = true;
      }];
    };

    # Peer auth with role switching (home-scout precedent).
    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -tAc 'GRANT research_scout TO ${cfg.user}' || true
    '';

    #--------------------------------------------------------------------------
    # Unified server
    #--------------------------------------------------------------------------
    systemd.services.research-scout = {
      description = "Research Scout MCP + HTTP Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        HWC_NOTIFY_URL = cfg.notifyUrl;
        # The classifier shells out to the `claude` CLI (scout precedent:
        # unit PATH carries only nodejs, so the binary must be declared).
        CLAUDE_BIN = "/etc/profiles/per-user/${cfg.user}/bin/claude";
        # Hardened unit must never write frontend/dist — deploy prebuilds it.
        SKIP_FRONTEND_BUILD = "1";
      };

      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type             = "simple";
        ExecStart        = "${node} ${tsx} ${cli} serve --port ${toString cfg.port}";
        WorkingDirectory = cfg.projectDir;
        User             = cfg.user;
        Restart          = "on-failure";
        RestartSec       = "5s";

        NoNewPrivileges        = true;
        PrivateTmp             = true;
        ProtectSystem          = "strict";
        ProtectHome            = "read-only";
        ProtectKernelTunables  = true;
        ProtectKernelModules   = true;
        ProtectControlGroups   = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces     = true;
        RestrictRealtime       = true;
        RestrictSUIDSGID       = true;
        LockPersonality        = true;

        ReadWritePaths = [ "/tmp" ];
      };
    };

    #--------------------------------------------------------------------------
    # Ingest timer (Python, working-tree deploy like the node service)
    #--------------------------------------------------------------------------
    systemd.services.research-scout-arxiv = {
      description = "Research Scout daily arXiv ingest";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      environment = ingestEnv;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = "${cfg.projectDir}/ingest";
        ExecStart = "${ingestPython}/bin/python -m researchscout_ingest.arxiv_run";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
      };
    };
    systemd.timers.research-scout-arxiv = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # 05:15 MT: after arXiv's Mon-Fri ~20:00 ET announcement, before the
        # 03:15 NEXT-day classify sweep picks papers up — and offset from
        # home-scout's 06:20 harvest.
        OnCalendar = "*-*-* 05:15:00";
        RandomizedDelaySec = "30min";
        Persistent = true;
      };
    };
  };
}
