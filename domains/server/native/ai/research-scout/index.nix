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

  # One producer for the database name. It was spelled four times (option
  # default, ensureDatabases, ensureUsers, the grant); the per-database backup
  # registration below is the fifth consumer, which is where a repeated
  # literal stops being harmless.
  dbName = "research_scout";

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
      default = "postgresql://${dbName}@localhost/${dbName}";
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

    refineryIntakeUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8060/intake";
      description = "Refinery engine intake endpoint (weekly-digest distilled ideas)";
    };

    brainVaultDir = lib.mkOption {
      type = lib.types.path;
      default = if config.hwc.paths.brain.vault != null then config.hwc.paths.brain.vault
                else "${config.hwc.paths.user.home}/900_vaults/brain";
      description = "Brain vault clone the weekly-digest brain sink writes into (_library/research_feed)";
    };

    workflowContextVaultDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.hwc.paths.user.home}/900_vaults/brain/tech/wiki"
        "${config.hwc.paths.user.home}/900_vaults/brain/_charter"
      ];
      description = ''
        Vault subtrees the weekly workflow-suggestions sink reads to learn
        which systems the reader runs. Scanned recursively for .md, bounded
        per-file and in total by the app.

        Deliberately narrow: the sink's value is a small, current input the
        model can reason over, so this points at the documented-systems
        subtrees rather than the whole vault. Read-only — the unit keeps
        ProtectHome=read-only and this path is not in ReadWritePaths.
      '';
    };

    workflowContextFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.hwc.paths.user.home}/.claude/CLAUDE.md"
        "${config.hwc.paths.user.home}/600_apps/scout/CLAUDE.md"
        "${config.hwc.paths.user.home}/700_datax/CLAUDE.md"
        "${config.hwc.paths.user.home}/.nixos/CLAUDE.md"
      ];
      description = ''
        Individual files included whole in the suggestions grounding — the
        repo CLAUDE.md files, which state conventions and constraints in
        force. Missing paths are skipped, not errors, so this list can name
        repos that are not checked out on every host.
      '';
    };

    arxivCategories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cs.AI" "cs.CL" "cs.SE" "cs.MA" "cs.IR" "cs.DB" ];
      description = ''
        Bootstrap seed for the arXiv category list (G0-calibrated 2026-07-19;
        cs.LG and stat.ML dropped 2026-08-16 on measured yield).

        Insert-only: the DB ingest_sources table owns the live set; curate
        via the Settings UI / research_sources_* tools, not here. This seed
        only governs a fresh install, so a change here must be matched by a
        toggle on any host already running.

        Yield over the week to 2026-08-16, llm_engineering_v1: cs.LG scored
        428 items for 10 read_now (2.3%) and stat.ML 23 for 0 (0%) — together
        39% of the scoring volume for 9% of the hits. cs.IR by contrast hit
        20%. The dropped categories are the ones where the classifier spends
        the most and finds the least.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Database on the shared Postgres instance
    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [{
        name = dbName;
        ensureDBOwnership = true;
      }];
    };

    # Peer auth with role switching (home-scout precedent).
    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -tAc 'GRANT ${dbName} TO ${cfg.user}' || true
    '';

    # NO per-database backup registration here, deliberately (Law 15: exactly
    # one mechanism per backup concern).
    #
    # 2026-08-26: a premortem claimed research_scout had no backup, because
    # postgresql-db-backup dumps only datax/datax_monitor/hwc and the Postgres
    # data dir is in no borg source path. That claim was WRONG and the
    # registration it justified was reverted the same day. The borg job's own
    # pre-hook runs `pg_dumpall` into /var/lib/backups, which IS a borg source;
    # `CREATE DATABASE research_scout` is present in
    # /var/lib/backups/postgresql-2026-08-26.sql.gz, and that file is inside
    # archive hwc-server-hwc-backup-2026-08-26T02:19:57. Verify there, not in
    # postgresql-db-backup, before concluding a database here is unprotected.
    #
    # Registering a second dump would write the same fact twice into
    # /home/eric/backups/postgres, which is NOT a borg source — extra disk on
    # the exact drive whose loss is the scenario, and zero added durability.

    #--------------------------------------------------------------------------
    # Unified server
    #--------------------------------------------------------------------------
    systemd.services.research-scout = {
      description = "Research Scout MCP + HTTP Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # 2026-08-26 premortem: alerts.sources.serviceFailures.autoDetect covers a
      # hardcoded list that no scout unit is on, so Restart=on-failure retried
      # forever in silence. Declare the notifier in the module that owns the
      # unit (crm leadscout-ingest precedent).
      onFailure = lib.mkIf (config.hwc.monitoring.alerts.enable or false)
        [ "hwc-service-failure-notifier@research-scout.service" ];

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        HWC_NOTIFY_URL = cfg.notifyUrl;
        # Weekly-digest export sinks (behavior knobs live in the app's
        # digest_sinks setting; these are the host endpoints only).
        REFINERY_INTAKE_URL = cfg.refineryIntakeUrl;
        BRAIN_VAULT_DIR = toString cfg.brainVaultDir;
        # Grounding for the weekly workflow-suggestions email. Colon-joined,
        # PATH-style; the app skips entries that do not exist on this host.
        WORKFLOW_CONTEXT_VAULT_DIRS = lib.concatStringsSep ":" cfg.workflowContextVaultDirs;
        WORKFLOW_CONTEXT_FILES = lib.concatStringsSep ":" cfg.workflowContextFiles;
        # The classifier shells out to the `claude` CLI (scout precedent:
        # unit PATH carries only nodejs, so the binary must be declared).
        CLAUDE_BIN = "/etc/profiles/per-user/${cfg.user}/bin/claude";
        # Item scoring runs on the self-hosted DX1 model via its OpenAI-
        # compatible endpoint — 60 abstracts a day is a volume job, and it was
        # burning the Claude subscription. The suggestions sink deliberately
        # stays on claude-cli (its digest_sinks setting), because deciding what
        # is worth changing is the one call here where reasoning is the product.
        #
        # The key is read from the agenix mount rather than an EnvironmentFile:
        # systemd's `environment` cannot read a file, and an EnvironmentFile
        # would mean a second plaintext copy. The service user is in `secrets`,
        # so it can read the 0440 root:secrets mount directly.
        OPENAI_API_KEY_FILE = "/run/agenix/pi-dx1-api-key";
        OPENAI_BASE_URL = "https://dx1.datax.to/v1";
        OPENAI_MODEL = "dx1";
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

        # Backstop for the app's own 10s SIGTERM drain; deliberately NOT
        # SuccessExitStatus=143. Rationale in domains/server/README.md
        # (2026-08-15) — it governs all three scouts, so it lives one layer up.
        TimeoutStopSec   = "30s";

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

        # Vault subtree writable through ProtectHome=read-only — the digest
        # brain sink writes _library/research_feed notes there.
        ReadWritePaths = [ "/tmp" (toString cfg.brainVaultDir) ];
      };
    };

    #--------------------------------------------------------------------------
    # Ingest timer (Python, working-tree deploy like the node service)
    #--------------------------------------------------------------------------
    systemd.services.research-scout-arxiv = {
      description = "Research Scout daily arXiv ingest";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      # A oneshot that exits non-zero leaves no process to notice. Zero new
      # items is also a NORMAL arXiv weekend (2026-08-19, 08-22, 08-23 each
      # recorded 12 completed classify runs with items_selected = 0), so the
      # symptom carries no signal. The notifier is the only thing that
      # separates "broke" from "quiet".
      onFailure = lib.mkIf (config.hwc.monitoring.alerts.enable or false)
        [ "hwc-service-failure-notifier@research-scout-arxiv.service" ];
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
