# domains/business/datax-monitor/index.nix
#
# DataX Monitor — standalone DX1 agent-execution diagnostic dashboard.
#
# NAMESPACE: hwc.business.dataxMonitor.*
#
# Native (out-of-store) Node app at ~/projects/datax-monitor, run in place with
# `node tsx` — same pattern as domains/server/native/ai/lead-scout. One Hono
# server on :4400 serves BOTH the REST API (/api/*) and the built React SPA
# (ui/dist via UI_DIST), so externally it is a single name-based Caddy vhost
# (monitor.<vhostDomain>) — see domains/networking/routes.nix.
#
# Units:
#   - datax-monitor-migrate  (oneshot, before the API) applies src/store/schema.sql
#   - datax-monitor          (long-running API + dashboard on :4400)
#   - datax-monitor-ingest   (oneshot) + .timer (every 4h) Firestore→classify→Postgres
#
# Secrets (mounted by the generated secrets layer at /run/agenix/<name>):
#   - datax-monitor-fb-email / datax-monitor-fb-key  (NEW — Firebase service account)
#   - opensearch-host / opensearch-user / opensearch-pw  (REUSED — shared DataX OpenSearch,
#     same ones domains/home/apps/dxlog consumes; enrichment is optional/degrades to null)
#
# DEPENDENCIES:
#   - hwc.data.databases.postgresql (engine must be enabled)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.business.dataxMonitor;
  node = "/run/current-system/sw/bin/node";
  tsx = "${cfg.projectDir}/node_modules/tsx/dist/cli.mjs";

  # Shell preamble that loads runtime secrets from the agenix mounts into the
  # (auto-exported) environment, then the caller execs node. Mirrors the
  # read_secret helper in domains/home/apps/dxlog. The service user (eric) is in
  # the `secrets` group, so it can read the root:secrets 0440 mounts.
  secretEnv = ''
    secret_dir=/run/agenix
    read_secret() {
      f="$secret_dir/$1"
      if [ -r "$f" ]; then
        cat "$f"
      else
        echo "datax-monitor: missing/unreadable secret: $f" >&2
        echo "  (is eric in the 'secrets' group? has nixos-rebuild run since the secret was added?)" >&2
        exit 1
      fi
    }
    set -a
    FIREBASE_CLIENT_EMAIL="$(read_secret ${cfg.firebaseEmailSecret})"
    FIREBASE_PRIVATE_KEY="$(read_secret ${cfg.firebaseKeySecret})"
    OPENSEARCH_HOST="$(read_secret ${cfg.opensearchHostSecret})"
    OPENSEARCH_USER="$(read_secret ${cfg.opensearchUserSecret})"
    OPENSEARCH_PASSWORD="$(read_secret ${cfg.opensearchPasswordSecret})"
    OPENSEARCH_PORT="${cfg.opensearchPort}"
    set +a
  '';

  serveScript = pkgs.writeShellScript "datax-monitor-serve" ''
    set -eu
    ${secretEnv}
    exec ${node} ${tsx} ${cfg.projectDir}/src/api/main.ts
  '';

  ingestScript = pkgs.writeShellScript "datax-monitor-ingest" ''
    set -eu
    ${secretEnv}
    exec ${node} ${tsx} ${cfg.projectDir}/src/cron/ingest-job.ts
  '';

  migrateScript = pkgs.writeShellScript "datax-monitor-migrate" ''
    set -eu
    exec ${node} ${tsx} ${cfg.projectDir}/src/store/migrate.ts
  '';

  # Shared systemd hardening (mirrors lead-scout). The app only reads its
  # project dir and talks to Postgres over the socket + HTTPS out — no disk writes.
  hardening = {
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
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.business.dataxMonitor = {
    enable = lib.mkEnableOption "DataX Monitor — DX1 agent-execution diagnostic dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4400;
      description = "Port the Hono API+dashboard server listens on.";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/projects/datax-monitor";
      description = "Path to the datax-monitor project checkout (run in place).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the services as (must be in the 'secrets' group).";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "datax_monitor";
      description = "Local Postgres database name.";
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Postgres LOGIN role the app connects as (socket peer auth).";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql:///datax_monitor";
      description = "PostgreSQL connection string (default = local socket, peer auth).";
    };

    firebaseEmailSecret = lib.mkOption {
      type = lib.types.str;
      default = "datax-monitor-fb-email";
      description = "agenix secret NAME holding the Firebase service-account client email.";
    };

    firebaseKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "datax-monitor-fb-key";
      description = "agenix secret NAME holding the Firebase service-account private key (\\n-escaped).";
    };

    firebaseProjectId = lib.mkOption {
      type = lib.types.str;
      default = "jt-supercharged-db";
      description = "Firebase / Firestore project id (not secret).";
    };

    opensearchHostSecret = lib.mkOption {
      type = lib.types.str;
      default = "opensearch-host";
      description = "agenix secret NAME for the shared DataX OpenSearch host (reused).";
    };

    opensearchUserSecret = lib.mkOption {
      type = lib.types.str;
      default = "opensearch-user";
      description = "agenix secret NAME for the shared DataX OpenSearch user (reused).";
    };

    opensearchPasswordSecret = lib.mkOption {
      type = lib.types.str;
      default = "opensearch-pw";
      description = "agenix secret NAME for the shared DataX OpenSearch password (reused).";
    };

    opensearchPort = lib.mkOption {
      type = lib.types.str;
      default = "25060";
      description = "OpenSearch port (DigitalOcean managed; matches dxlog).";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # --- Postgres database + login role -------------------------------------
    services.postgresql.ensureDatabases = [ cfg.databaseName ];

    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -c "DO \$\$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${cfg.databaseUser}') THEN
          CREATE ROLE ${cfg.databaseUser} LOGIN;
        END IF;
      END \$\$;" || true
      $PSQL -d ${cfg.databaseName} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.databaseName} TO ${cfg.databaseUser};" || true
      $PSQL -d ${cfg.databaseName} -c "GRANT USAGE, CREATE ON SCHEMA public TO ${cfg.databaseUser};" || true
    '';

    hwc.data.databases.postgresql.backup.perDatabase.databases = [ cfg.databaseName ];

    # --- Migration (oneshot, before the API) --------------------------------
    systemd.services.datax-monitor-migrate = {
      description = "DataX Monitor — DB migration (applies schema.sql)";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "datax-monitor.service" ];
      path = [ pkgs.nodejs ];
      environment = {
        DATABASE_URL = cfg.databaseUrl;
        NODE_ENV = "production";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${migrateScript}";
        WorkingDirectory = cfg.projectDir;
        User = cfg.user;
      } // hardening;
    };

    # --- API + dashboard (long-running) -------------------------------------
    systemd.services.datax-monitor = {
      description = "DataX Monitor — API + dashboard (:${toString cfg.port})";
      after = [ "network-online.target" "postgresql.service" "datax-monitor-migrate.service" ];
      wants = [ "network-online.target" ];
      requires = [ "datax-monitor-migrate.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.nodejs ];
      environment = {
        DATABASE_URL = cfg.databaseUrl;
        PORT = toString cfg.port;
        NODE_ENV = "production";
        FIREBASE_PROJECT_ID = cfg.firebaseProjectId;
        UI_DIST = "${cfg.projectDir}/ui/dist";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${serveScript}";
        WorkingDirectory = cfg.projectDir;
        User = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";
      } // hardening;
    };

    # --- Ingest job (oneshot) + 4h timer ------------------------------------
    systemd.services.datax-monitor-ingest = {
      description = "DataX Monitor — Firestore ingest + classify";
      after = [ "network-online.target" "postgresql.service" "datax-monitor-migrate.service" ];
      wants = [ "network-online.target" ];
      requires = [ "datax-monitor-migrate.service" ];
      path = [ pkgs.nodejs ];
      environment = {
        DATABASE_URL = cfg.databaseUrl;
        NODE_ENV = "production";
        FIREBASE_PROJECT_ID = cfg.firebaseProjectId;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ingestScript}";
        WorkingDirectory = cfg.projectDir;
        User = cfg.user;
      } // hardening;
    };

    systemd.timers.datax-monitor-ingest = {
      description = "DataX Monitor — ingest every 4h";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/4:00:00";
        Persistent = true;
        RandomizedDelaySec = 300;
      };
    };

    assertions = [
      {
        assertion = config.hwc.data.databases.postgresql.enable;
        message = ''
          hwc.business.dataxMonitor requires hwc.data.databases.postgresql to be enabled.
        '';
      }
    ];
  };
}
