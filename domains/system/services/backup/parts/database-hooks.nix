# domains/system/services/backup/parts/database-hooks.nix
# Database consistency framework for atomic backups
# Provides pre/post hooks for database dumps and crash-consistent snapshots

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

  # PostgreSQL backup hook (WAL archiving + base backup)
  postgresBackupHook = pkgs.writeScriptBin "postgres-backup-hook" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    BACKUP_DIR="$1"
    ACTION="$2"  # pre or post

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] POSTGRES: $1"
    }

    if [[ "$ACTION" == "pre" ]]; then
      log "Starting PostgreSQL consistent backup..."

      # Create pg_basebackup for PITR capability
      PGDATA_BACKUP="$BACKUP_DIR/postgres-basebackup"
      ${pkgs.coreutils}/bin/mkdir -p "$PGDATA_BACKUP"

      if ${pkgs.systemd}/bin/systemctl is-active postgresql >/dev/null 2>&1; then
        log "Creating base backup with WAL archiving..."

        # Use pg_basebackup for crash-consistent backup
        sudo -u postgres ${pkgs.postgresql}/bin/pg_basebackup \
          -D "$PGDATA_BACKUP" \
          -F tar \
          -X stream \
          -z \
          -P \
          -v || {
            log "ERROR: pg_basebackup failed"
            exit 1
          }

        # Also create SQL dump for portability
        log "Creating SQL dump for portability..."
        sudo -u postgres ${pkgs.postgresql}/bin/pg_dumpall \
          | ${pkgs.gzip}/bin/gzip -c > "$BACKUP_DIR/postgres-dump.sql.gz"

        # Save PostgreSQL version info
        sudo -u postgres ${pkgs.postgresql}/bin/psql -c "SELECT version();" \
          > "$BACKUP_DIR/postgres-version.txt"

        log "✓ PostgreSQL backup completed"
      else
        log "PostgreSQL not running, skipping"
      fi

    elif [[ "$ACTION" == "post" ]]; then
      log "PostgreSQL post-backup cleanup..."
      # Nothing to do for pg_basebackup
      log "✓ Post-backup complete"
    fi
  '';

  # MySQL/MariaDB backup hook
  mysqlBackupHook = pkgs.writeScriptBin "mysql-backup-hook" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    BACKUP_DIR="$1"
    ACTION="$2"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] MYSQL: $1"
    }

    if [[ "$ACTION" == "pre" ]]; then
      log "Starting MySQL consistent backup..."

      if ${pkgs.systemd}/bin/systemctl is-active mysql >/dev/null 2>&1; then
        # Use mysqldump with single-transaction for InnoDB consistency
        log "Creating MySQL dump..."
        ${pkgs.mariadb}/bin/mysqldump \
          --all-databases \
          --single-transaction \
          --quick \
          --lock-tables=false \
          --routines \
          --triggers \
          --events \
          | ${pkgs.gzip}/bin/gzip -c > "$BACKUP_DIR/mysql-dump.sql.gz"

        log "✓ MySQL backup completed"
      else
        log "MySQL not running, skipping"
      fi
    fi
  '';

  # Redis backup hook
  redisBackupHook = pkgs.writeScriptBin "redis-backup-hook" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    BACKUP_DIR="$1"
    ACTION="$2"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] REDIS: $1"
    }

    if [[ "$ACTION" == "pre" ]]; then
      log "Starting Redis backup..."

      if ${pkgs.systemd}/bin/systemctl is-active redis >/dev/null 2>&1; then
        # Trigger BGSAVE for consistent snapshot
        ${pkgs.redis}/bin/redis-cli BGSAVE

        # Wait for BGSAVE to complete
        while ${pkgs.redis}/bin/redis-cli LASTSAVE | ${pkgs.gnugrep}/bin/grep -q "$(${pkgs.redis}/bin/redis-cli LASTSAVE)"; do
          ${pkgs.coreutils}/bin/sleep 1
        done

        # Copy RDB file
        REDIS_DIR="/var/lib/redis"
        if [[ -f "$REDIS_DIR/dump.rdb" ]]; then
          ${pkgs.coreutils}/bin/cp -p "$REDIS_DIR/dump.rdb" "$BACKUP_DIR/redis-dump.rdb"
          log "✓ Redis backup completed"
        fi
      else
        log "Redis not running, skipping"
      fi
    fi
  '';

  # Docker volumes backup hook
  dockerBackupHook = pkgs.writeScriptBin "docker-backup-hook" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    BACKUP_DIR="$1"
    ACTION="$2"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] DOCKER: $1"
    }

    if [[ "$ACTION" == "pre" ]]; then
      log "Starting Docker volumes backup..."

      if ${pkgs.systemd}/bin/systemctl is-active docker >/dev/null 2>&1; then
        DOCKER_BACKUP="$BACKUP_DIR/docker-volumes"
        ${pkgs.coreutils}/bin/mkdir -p "$DOCKER_BACKUP"

        # List all volumes
        for volume in $(${pkgs.docker}/bin/docker volume ls -q); do
          log "Backing up volume: $volume"

          # Create tar archive of volume
          ${pkgs.docker}/bin/docker run --rm \
            -v "$volume:/volume" \
            -v "$DOCKER_BACKUP:/backup" \
            alpine tar czf "/backup/$volume.tar.gz" -C /volume . || {
              log "WARNING: Failed to backup volume $volume"
            }
        done

        log "✓ Docker volumes backup completed"
      else
        log "Docker not running, skipping"
      fi
    fi
  '';

  # Combined database hook wrapper
  databaseBackupWrapper = pkgs.writeScriptBin "database-backup-wrapper" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    BACKUP_DIR="$1"
    ACTION="$2"  # pre or post

    # Create database backup directory
    DB_BACKUP_DIR="$BACKUP_DIR/.database-backups"
    ${pkgs.coreutils}/bin/mkdir -p "$DB_BACKUP_DIR"

    echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] Starting database consistency hooks ($ACTION)..."

    # Run enabled database hooks
    ${lib.optionalString cfg.database.postgres.enable ''
      ${postgresBackupHook}/bin/postgres-backup-hook "$DB_BACKUP_DIR" "$ACTION"
    ''}

    ${lib.optionalString cfg.database.mysql.enable ''
      ${mysqlBackupHook}/bin/mysql-backup-hook "$DB_BACKUP_DIR" "$ACTION"
    ''}

    ${lib.optionalString cfg.database.redis.enable ''
      ${redisBackupHook}/bin/redis-backup-hook "$DB_BACKUP_DIR" "$ACTION"
    ''}

    ${lib.optionalString cfg.database.docker.enable ''
      ${dockerBackupHook}/bin/docker-backup-hook "$DB_BACKUP_DIR" "$ACTION"
    ''}

    echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] Database hooks completed ($ACTION)"
  '';

in
{
  config = lib.mkIf cfg.enable {
    # Install database backup hooks if any are enabled
    environment.systemPackages = lib.optionals (
      cfg.database.postgres.enable ||
      cfg.database.mysql.enable ||
      cfg.database.redis.enable ||
      cfg.database.docker.enable
    ) [
      databaseBackupWrapper
      postgresBackupHook
      mysqlBackupHook
      redisBackupHook
      dockerBackupHook
    ];

    # Assertions for database backup requirements
    assertions = [
      {
        assertion = !cfg.database.postgres.enable || config.services.postgresql.enable or false;
        message = "PostgreSQL backup enabled but PostgreSQL service is not running";
      }
      {
        assertion = !cfg.database.mysql.enable || config.services.mysql.enable or false;
        message = "MySQL backup enabled but MySQL service is not running";
      }
      {
        assertion = !cfg.database.redis.enable || config.services.redis.servers != {} or false;
        message = "Redis backup enabled but Redis service is not running";
      }
      {
        assertion = !cfg.database.docker.enable || config.virtualisation.docker.enable or false;
        message = "Docker backup enabled but Docker is not enabled";
      }
    ];
  };
}
