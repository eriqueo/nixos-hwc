# Server backup scripts - automated backup of containers, databases, and configuration
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.backup;

  # Backup script for containers
  containerBackupScript = pkgs.writeScriptBin "backup-containers" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BACKUP_DIR="${config.hwc.paths.hot.root}/backups/containers"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETENTION_DAYS=30

    echo "=== Container Backup Started at $(date) ==="

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup container volumes
    for container in $(${pkgs.podman}/bin/podman ps --format '{{.Names}}'); do
      echo "Backing up $container..."

      # Export container config
      ${pkgs.podman}/bin/podman inspect "$container" > "$BACKUP_DIR/$container-config-$DATE.json"

      # Backup container volumes
      VOLUMES=$(${pkgs.podman}/bin/podman inspect "$container" | ${pkgs.jq}/bin/jq -r '.[].Mounts[].Source' | grep -v '^$' || true)

      if [ -n "$VOLUMES" ]; then
        echo "$VOLUMES" | while read volume; do
          volume_name=$(basename "$volume")
          echo "  Backing up volume: $volume_name"
          ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/$container-$volume_name-$DATE.tar.gz" -C "$(dirname "$volume")" "$volume_name"
        done
      fi
    done

    # Clean up old backups
    echo "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

    echo "=== Container Backup Completed at $(date) ==="
  '';

  # Backup script for databases
  databaseBackupScript = pkgs.writeScriptBin "backup-databases" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BACKUP_DIR="${config.hwc.paths.hot.root}/backups/databases"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETENTION_DAYS=30

    echo "=== Database Backup Started at $(date) ==="

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup CouchDB
    if systemctl is-active --quiet couchdb; then
      echo "Backing up CouchDB..."
      ${pkgs.curl}/bin/curl -X GET http://127.0.0.1:5984/_all_dbs | ${pkgs.jq}/bin/jq -r '.[]' | while read db; do
        if [ "$db" != "_replicator" ] && [ "$db" != "_users" ]; then
          echo "  Backing up database: $db"
          ${pkgs.curl}/bin/curl -X GET "http://127.0.0.1:5984/$db/_all_docs?include_docs=true" > "$BACKUP_DIR/couchdb-$db-$DATE.json"
        fi
      done
    fi

    # Backup Immich database (if running)
    if systemctl is-active --quiet immich-server; then
      echo "Backing up Immich PostgreSQL database..."
      sudo -u postgres ${pkgs.postgresql}/bin/pg_dump immich > "$BACKUP_DIR/immich-$DATE.sql"
    fi

    # Clean up old backups
    echo "Cleaning up database backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

    echo "=== Database Backup Completed at $(date) ==="
  '';

  # System configuration backup
  systemBackupScript = pkgs.writeScriptBin "backup-system" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BACKUP_DIR="${config.hwc.paths.hot.root}/backups/system"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETENTION_DAYS=90

    echo "=== System Backup Started at $(date) ==="

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup system configuration
    echo "Backing up NixOS configuration..."
    NIXOS_DIR="${config.hwc.paths.nixos}"
    if [ -d "$NIXOS_DIR" ]; then
      ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/nixos-config-$DATE.tar.gz" -C "$(dirname "$NIXOS_DIR")" "$(basename "$NIXOS_DIR")"
    fi

    # Backup important system files
    echo "Backing up system state..."
    ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/system-state-$DATE.tar.gz" \
      /etc/nixos \
      /etc/age \
      /var/lib/systemd \
      /etc/machine-id \
      2>/dev/null || true

    # List installed packages
    echo "Saving package list..."
    nix-env -q > "$BACKUP_DIR/packages-$DATE.txt"

    # Save system info
    echo "Saving system information..."
    {
      echo "Hostname: $(hostname)"
      echo "Kernel: $(uname -r)"
      echo "NixOS Version: $(nixos-version)"
      echo "Backup Date: $(date)"
      df -h
      free -h
    } > "$BACKUP_DIR/system-info-$DATE.txt"

    # Clean up old backups
    echo "Cleaning up system backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

    echo "=== System Backup Completed at $(date) ==="
  '';

  # Master backup script
  masterBackupScript = pkgs.writeScriptBin "backup-all" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "======================================"
    echo "Starting Full Server Backup"
    echo "======================================"

    # Run all backup scripts
    ${systemBackupScript}/bin/backup-system
    ${databaseBackupScript}/bin/backup-databases
    ${containerBackupScript}/bin/backup-containers

    echo "======================================"
    echo "Full Server Backup Completed"
    echo "======================================"
  '';

in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      systemBackupScript
      databaseBackupScript
      containerBackupScript
      masterBackupScript
    ];

    # Systemd service for automated backups
    systemd.services.server-backup = {
      description = "Automated server backup (containers, databases, system)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${masterBackupScript}/bin/backup-all";
        User = "root";
      };
    };

    # Timer for daily backups
    systemd.timers.server-backup = {
      description = "Daily server backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        OnBootSec = "15min";  # Run 15 minutes after boot
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };

    # Create backup directories
    systemd.tmpfiles.rules = [
      "d ${config.hwc.paths.hot.root}/backups 0755 root root -"
      "d ${config.hwc.paths.hot.root}/backups/containers 0755 root root -"
      "d ${config.hwc.paths.hot.root}/backups/databases 0755 root root -"
      "d ${config.hwc.paths.hot.root}/backups/system 0755 root root -"
    ];
  };
}
