# domains/data/databases/index.nix
#
# Database services - PostgreSQL, Redis, InfluxDB
#
# NAMESPACE: hwc.data.databases.*
#
# DEPENDENCIES:
#   - hwc.paths (for dataDir defaults)
#
# USED BY:
#   - Containers: immich, paperless, firefly
#   - Native services: n8n, business APIs
#   - profiles/server.nix, profiles/business.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.data.databases;
  paths = config.hwc.paths;
in
{
  # OPTIONS
  options.hwc.data.databases = {
    postgresql = {
      enable = lib.mkEnableOption "PostgreSQL database";

      version = lib.mkOption {
        type = lib.types.str;
        default = "15";
        description = ''
          Expected PostgreSQL major version. Used by the version-drift
          assertion to detect accidental package changes (data directory
          format is not upward-compatible — pg_upgrade required).

          Must match the major version of `package`.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.postgresql_15;
        defaultText = lib.literalExpression "pkgs.postgresql_15";
        example = lib.literalExpression "pkgs.postgresql_17";
        description = ''
          PostgreSQL package. Default pins to 15 because the server's
          cluster is initialized in 15 format and changing it would
          require pg_upgrade.

          Override per machine when the cluster is fresh (or has been
          migrated): e.g. laptop sets `pkgs.postgresql_17`.
        '';
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state or "/var/lib"}/postgresql";
        description = "PostgreSQL data directory";
      };

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Databases to create";
      };

      extensions = lib.mkOption {
        type = lib.types.functionTo (lib.types.listOf lib.types.package);
        default = _ps: [];
        defaultText = lib.literalExpression "ps: []";
        example = lib.literalExpression "ps: [ ps.pgvector ps.vectorchord ]";
        description = "PostgreSQL extensions to install (function over postgresqlPackages).";
      };

      sharedPreloadLibraries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "vchord" ];
        description = "Libraries to add to shared_preload_libraries.";
      };

      containerNetwork = {
        enable = lib.mkEnableOption ''
          Podman media-network integration:
            - bind 10.89.0.1 in addition to localhost
            - add 10.89.0.0/16 host-based auth rule
            - order postgresql after init-media-network.service
        '';
      };

      backup = {
        enable = lib.mkEnableOption "Automatic pg_dumpall backups (all databases)";

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Backup schedule for pg_dumpall";
        };

        # Per-database backups with compression and retention
        perDatabase = {
          enable = lib.mkEnableOption "Per-database compressed backups";

          databases = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = [ "hwc" "n8n" ];
            description = "Specific databases to backup individually";
          };

          outputDir = lib.mkOption {
            type = lib.types.path;
            default = "${paths.user.home}/backups/postgres";
            description = "Directory for per-database backups";
          };

          compress = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Compress backups with gzip";
          };

          retentionDays = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "Delete backups older than this many days";
          };

          schedule = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 02:30:00";
            description = "Systemd calendar expression for backup schedule";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "eric";
            description = "User to run backups as (must have DB access)";
          };
        };
      };
    };

    redis = {
      enable = lib.mkEnableOption "Redis cache";

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };

      bind = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1 10.89.0.1";
        description = "Bind addresses for Redis (include media-network gateway for containers)";
      };

      maxMemory = lib.mkOption {
        type = lib.types.str;
        default = "2gb";
        description = "Maximum memory";
      };
    };

    influxdb = {
      enable = lib.mkEnableOption "InfluxDB time-series database";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "InfluxDB port";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    # PostgreSQL
    (lib.mkIf cfg.postgresql.enable {
      services.postgresql = {
        enable = true;
        # Version drift is caught by the assertion below: cluster's on-disk
        # format must match cfg.postgresql.version (server is locked to 15).
        package = cfg.postgresql.package;
        extensions = cfg.postgresql.extensions;
        dataDir = cfg.postgresql.dataDir;

        ensureDatabases = cfg.postgresql.databases;

        settings = lib.mkMerge [
          {
            listen_addresses = lib.mkForce (
              if cfg.postgresql.containerNetwork.enable
              then "localhost,10.89.0.1"
              else "localhost"
            );
          }
          (lib.mkIf (cfg.postgresql.sharedPreloadLibraries != []) {
            shared_preload_libraries =
              lib.concatStringsSep "," cfg.postgresql.sharedPreloadLibraries;
          })
        ];

        authentication = ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
        '' + lib.optionalString cfg.postgresql.containerNetwork.enable ''
          # Allow connections from Podman media-network (10.89.0.0/16)
          host all all 10.89.0.0/16 trust
        '';
      };

      # PostgreSQL listens on 10.89.0.1 (Podman network gateway) — wait for it
      systemd.services.postgresql = lib.mkIf cfg.postgresql.containerNetwork.enable {
        after = [ "init-media-network.service" ];
        wants = [ "init-media-network.service" ];
      };

      # NixOS's postgresql module uses systemd namespace sandboxing with
      # ReadWritePaths=dataDir but only sets StateDirectory for the default
      # /var/lib/postgresql. For custom dataDir, the path must exist before
      # unit start or namespace setup fails (status=226/NAMESPACE).
      systemd.tmpfiles.rules = [
        "d ${cfg.postgresql.dataDir} 0700 postgres postgres - -"
      ];

      # Backup service
      systemd.services.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        description = "PostgreSQL backup";
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = "${pkgs.postgresql}/bin/pg_dumpall -f ${paths.backup}/postgresql-$(date +%Y%m%d).sql";
        };
      };

      systemd.timers.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.postgresql.backup.schedule;
          Persistent = true;
        };
      };

      # Per-database backup service
      systemd.services.postgresql-db-backup = lib.mkIf cfg.postgresql.backup.perDatabase.enable {
        description = "Backup specific PostgreSQL databases";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.postgresql.backup.perDatabase.user;
          Group = "users";
        };
        path = [ pkgs.postgresql pkgs.gzip pkgs.coreutils pkgs.findutils ];
        script = let
          backupCfg = cfg.postgresql.backup.perDatabase;
          ext = if backupCfg.compress then ".sql.gz" else ".sql";
        in ''
          set -euo pipefail
          BACKUP_DIR="${backupCfg.outputDir}"
          mkdir -p "$BACKUP_DIR"

          ${lib.concatMapStringsSep "\n" (db: ''
            echo "Backing up database: ${db}"
            BACKUP_FILE="$BACKUP_DIR/${db}_$(date +%Y-%m-%d)${ext}"
            ${if backupCfg.compress then ''
              pg_dump ${db} | gzip > "$BACKUP_FILE"
            '' else ''
              pg_dump ${db} > "$BACKUP_FILE"
            ''}
            if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
              SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
              echo "  Success: $BACKUP_FILE ($SIZE)"
            else
              echo "  ERROR: Backup failed for ${db}"
              exit 1
            fi
          '') backupCfg.databases}

          # Cleanup old backups
          echo "Cleaning up backups older than ${toString backupCfg.retentionDays} days..."
          ${lib.concatMapStringsSep "\n" (db: ''
            find "$BACKUP_DIR" -name "${db}_*${ext}" -mtime +${toString backupCfg.retentionDays} -delete
          '') backupCfg.databases}
          echo "Cleanup complete."
        '';
      };

      systemd.timers.postgresql-db-backup = lib.mkIf cfg.postgresql.backup.perDatabase.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.postgresql.backup.perDatabase.schedule;
          Persistent = true;
          RandomizedDelaySec = "15m";
        };
      };
    })

    # Redis
    (lib.mkIf cfg.redis.enable {
      services.redis.servers.main = {
        enable = true;
        port = cfg.redis.port;
        bind = cfg.redis.bind;
        settings = {
          protected-mode = "no";
          maxmemory = cfg.redis.maxMemory;
          maxmemory-policy = "allkeys-lru";
        };
      };

      # Redis binds to 10.89.0.1 (Podman network gateway). Ordering on
      # init-media-network is not sufficient: podman creates the network
      # object there, but the gateway IP only appears on the host when the
      # first attached container starts. Boot 2026-07-05 hit exactly this —
      # bind failed once and the unit stayed dead. Retry until the bridge
      # exists instead.
      systemd.services.redis-main = {
        after = [ "init-media-network.service" ];
        wants = [ "init-media-network.service" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
        };
        unitConfig.StartLimitIntervalSec = 0;
      };
    })

    # InfluxDB
    (lib.mkIf cfg.influxdb.enable {
      services.influxdb2 = {
        enable = true;
        settings = {
          http-bind-address = ":${toString cfg.influxdb.port}";
        };
      };

      networking.firewall.allowedTCPPorts = [ cfg.influxdb.port ];
    })

    # Validation
    (lib.mkIf cfg.postgresql.enable {
      assertions = [
        {
          assertion =
            builtins.match "${cfg.postgresql.version}\\..*"
              cfg.postgresql.package.version
            != null;
          message = ''
            ============================================================
            POSTGRESQL VERSION DRIFT DETECTED
            ============================================================
            Expected major version: ${cfg.postgresql.version}
            Actual package version: ${cfg.postgresql.package.version}

            `hwc.data.databases.postgresql.version` and `.package` must
            agree. The data directory is initialized in the package's
            on-disk format — switching majors requires pg_upgrade or
            dump+restore.

            To intentionally upgrade:
              1. Backup: pg_dumpall -f /backup/postgresql-pre-upgrade.sql
              2. Stop PostgreSQL: systemctl stop postgresql
              3. Migrate data: pg_upgrade or pg_dumpall/restore
              4. Update both `version` and `package` together
              5. Test thoroughly before applying

            See CHARTER.md section "Flake Update Strategy"
            ============================================================
          '';
        }
      ];
    })
  ];
}
