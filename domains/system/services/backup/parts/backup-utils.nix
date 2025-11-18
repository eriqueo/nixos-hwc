# domains/system/services/backup/parts/backup-utils.nix
# Backup utility scripts for status, restore, verification, and manual operations

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

  # Backup status script
  backupStatusScript = pkgs.writeScriptBin "backup-status" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
    LOG_DIR="${cfg.monitoring.logPath}"

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                     BACKUP SYSTEM STATUS                          ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Hostname: $HOSTNAME"
    echo "Date: $(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Local backup status
    ${lib.optionalString cfg.local.enable ''
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "LOCAL BACKUP (External Drive/NAS/DAS)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      BACKUP_DEST="${cfg.local.mountPoint}"
      BACKUP_ROOT="$BACKUP_DEST/$HOSTNAME"

      if ${pkgs.util-linux}/bin/mountpoint -q "$BACKUP_DEST" 2>/dev/null; then
        echo "✓ Backup destination mounted: $BACKUP_DEST"

        # Show disk usage
        echo ""
        echo "Disk Usage:"
        ${pkgs.coreutils}/bin/df -h "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==1 || NR==2'

        # Check for backups
        if [[ -d "$BACKUP_ROOT" ]]; then
          echo ""
          echo "Backup Snapshots:"

          # Count backups
          DAILY_COUNT=$(${pkgs.findutils}/bin/find "$BACKUP_ROOT/daily" -maxdepth 1 -type d 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
          WEEKLY_COUNT=$(${pkgs.findutils}/bin/find "$BACKUP_ROOT/weekly" -maxdepth 1 -type d 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
          MONTHLY_COUNT=$(${pkgs.findutils}/bin/find "$BACKUP_ROOT/monthly" -maxdepth 1 -type d 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)

          echo "  Daily backups:   $((DAILY_COUNT - 1))"
          echo "  Weekly backups:  $((WEEKLY_COUNT - 1))"
          echo "  Monthly backups: $((MONTHLY_COUNT - 1))"

          # Show latest backup
          if [[ -L "$BACKUP_ROOT/latest" ]]; then
            LATEST=$(${pkgs.coreutils}/bin/readlink "$BACKUP_ROOT/latest")
            LATEST_TIME=$(${pkgs.coreutils}/bin/stat -c %y "$BACKUP_ROOT/latest" | ${pkgs.coreutils}/bin/cut -d'.' -f1)
            LATEST_SIZE=$(${pkgs.coreutils}/bin/du -sh "$BACKUP_ROOT/latest" 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)

            echo ""
            echo "Latest Backup:"
            echo "  Time: $LATEST_TIME"
            echo "  Size: $LATEST_SIZE"
            echo "  Path: $LATEST"
          fi
        else
          echo "⚠ No backups found at $BACKUP_ROOT"
        fi
      else
        echo "✗ Backup destination NOT mounted: $BACKUP_DEST"
      fi
      echo ""
    ''}

    # Cloud backup status
    ${lib.optionalString cfg.cloud.enable ''
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "CLOUD BACKUP (${cfg.cloud.provider})"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      RCLONE_CONFIG="${if cfg.protonDrive.enable then "/etc/rclone-proton.conf" else "/root/.config/rclone/rclone.conf"}"
      REMOTE="${cfg.cloud.provider}:${cfg.cloud.remotePath}/$HOSTNAME"

      if [[ -f "$RCLONE_CONFIG" ]]; then
        echo "✓ Rclone config found: $RCLONE_CONFIG"

        # Test connection
        if ${pkgs.rclone}/bin/rclone --config="$RCLONE_CONFIG" lsd "${cfg.cloud.provider}:" >/dev/null 2>&1; then
          echo "✓ Cloud connection working"

          # Get remote size
          echo ""
          echo "Remote Backup Size:"
          ${pkgs.rclone}/bin/rclone --config="$RCLONE_CONFIG" size "$REMOTE" 2>/dev/null || echo "  (Unable to retrieve)"
        else
          echo "✗ Cloud connection FAILED"
        fi
      else
        echo "✗ Rclone config NOT found: $RCLONE_CONFIG"
      fi
      echo ""
    ''}

    # Systemd service status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SYSTEMD SERVICES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    ${lib.optionalString cfg.local.enable ''
      echo ""
      echo "Local Backup Service:"
      ${pkgs.systemd}/bin/systemctl status backup-local.service --no-pager -l 2>/dev/null || echo "  Not running"
    ''}

    ${lib.optionalString cfg.cloud.enable ''
      echo ""
      echo "Cloud Backup Service:"
      ${pkgs.systemd}/bin/systemctl status backup-cloud.service --no-pager -l 2>/dev/null || echo "  Not running"
    ''}

    ${lib.optionalString cfg.schedule.enable ''
      echo ""
      echo "Backup Timer:"
      ${pkgs.systemd}/bin/systemctl status backup.timer --no-pager -l 2>/dev/null || echo "  Not active"

      echo ""
      echo "Next Scheduled Backup:"
      ${pkgs.systemd}/bin/systemctl list-timers backup.timer --no-pager 2>/dev/null || echo "  No timer active"
    ''}

    # Recent logs
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "RECENT LOG ENTRIES (last 10)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for logfile in "$LOG_DIR"/*.log; do
      if [[ -f "$logfile" ]]; then
        echo "$(${pkgs.coreutils}/bin/basename "$logfile"):"
        ${pkgs.coreutils}/bin/tail -n 5 "$logfile" 2>/dev/null || echo "  (empty)"
        echo ""
      fi
    done
  '';

  # Backup now (manual trigger) script
  backupNowScript = pkgs.writeScriptBin "backup-now" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    echo "Starting manual backup..."
    echo ""

    SUCCESS=true

    # Run local backup if enabled
    ${lib.optionalString cfg.local.enable ''
      echo "Running local backup..."
      if ${pkgs.systemd}/bin/systemctl start backup-local.service; then
        echo "✓ Local backup completed"
      else
        echo "✗ Local backup failed"
        SUCCESS=false
      fi
      echo ""
    ''}

    # Run cloud backup if enabled
    ${lib.optionalString cfg.cloud.enable ''
      echo "Running cloud backup..."
      if ${pkgs.systemd}/bin/systemctl start backup-cloud.service; then
        echo "✓ Cloud backup completed"
      else
        echo "✗ Cloud backup failed"
        SUCCESS=false
      fi
      echo ""
    ''}

    if [[ "$SUCCESS" == true ]]; then
      echo "✓ All backups completed successfully"
      exit 0
    else
      echo "✗ Some backups failed. Check logs with 'backup-status'"
      exit 1
    fi
  '';

  # Restore script
  restoreScript = pkgs.writeScriptBin "backup-restore" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
    BACKUP_DEST="${cfg.local.mountPoint}"
    BACKUP_ROOT="$BACKUP_DEST/$HOSTNAME"

    # Function to show usage
    show_usage() {
      echo "Usage: backup-restore [OPTIONS] <snapshot> <source-path> <destination-path>"
      echo ""
      echo "Restore files from a backup snapshot"
      echo ""
      echo "OPTIONS:"
      echo "  -l, --list         List available backup snapshots"
      echo "  -h, --help         Show this help message"
      echo ""
      echo "EXAMPLES:"
      echo "  # List available backups"
      echo "  backup-restore --list"
      echo ""
      echo "  # Restore a file from the latest backup"
      echo "  backup-restore latest /home/user/Documents/file.txt /tmp/restored-file.txt"
      echo ""
      echo "  # Restore from a specific snapshot"
      echo "  backup-restore daily/2025-01-15_02-00-00 /home/user/.config /tmp/restored-config"
    }

    # List available backups
    list_backups() {
      if [[ ! -d "$BACKUP_ROOT" ]]; then
        echo "No backups found at $BACKUP_ROOT"
        exit 1
      fi

      echo "Available backup snapshots:"
      echo ""
      echo "Latest:"
      if [[ -L "$BACKUP_ROOT/latest" ]]; then
        ${pkgs.coreutils}/bin/ls -lh "$BACKUP_ROOT/latest" | ${pkgs.gawk}/bin/awk '{print "  " $NF}'
      fi
      echo ""

      echo "Daily backups:"
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/daily" -maxdepth 1 -type d -printf "  %f\n" 2>/dev/null | ${pkgs.gnused}/bin/sed '/^$/d' | ${pkgs.coreutils}/bin/sort -r
      echo ""

      echo "Weekly backups:"
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/weekly" -maxdepth 1 -type d -printf "  %f\n" 2>/dev/null | ${pkgs.gnused}/bin/sed '/^$/d' | ${pkgs.coreutils}/bin/sort -r
      echo ""

      echo "Monthly backups:"
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/monthly" -maxdepth 1 -type d -printf "  %f\n" 2>/dev/null | ${pkgs.gnused}/bin/sed '/^$/d' | ${pkgs.coreutils}/bin/sort -r
    }

    # Parse arguments
    if [[ $# -eq 0 ]]; then
      show_usage
      exit 1
    fi

    case "$1" in
      -l|--list)
        list_backups
        exit 0
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      -*)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac

    # Restore operation
    if [[ $# -lt 3 ]]; then
      echo "Error: Missing arguments"
      show_usage
      exit 1
    fi

    SNAPSHOT="$1"
    SOURCE_PATH="$2"
    DEST_PATH="$3"

    # Resolve snapshot path
    if [[ "$SNAPSHOT" == "latest" ]]; then
      SNAPSHOT_PATH="$BACKUP_ROOT/latest"
    else
      SNAPSHOT_PATH="$BACKUP_ROOT/$SNAPSHOT"
    fi

    # Check if snapshot exists
    if [[ ! -d "$SNAPSHOT_PATH" ]]; then
      echo "Error: Snapshot not found: $SNAPSHOT_PATH"
      echo ""
      echo "Available snapshots:"
      list_backups
      exit 1
    fi

    # Full source path in snapshot
    FULL_SOURCE="$SNAPSHOT_PATH$SOURCE_PATH"

    if [[ ! -e "$FULL_SOURCE" ]]; then
      echo "Error: Source path not found in snapshot: $FULL_SOURCE"
      exit 1
    fi

    # Perform restore
    echo "Restoring from snapshot: $SNAPSHOT"
    echo "Source: $SOURCE_PATH"
    echo "Destination: $DEST_PATH"
    echo ""

    if ${pkgs.rsync}/bin/rsync -aAXHv --progress "$FULL_SOURCE" "$DEST_PATH"; then
      echo ""
      echo "✓ Restore completed successfully"
      exit 0
    else
      echo ""
      echo "✗ Restore failed"
      exit 1
    fi
  '';

  # Verify backup script
  verifyBackupScript = pkgs.writeScriptBin "backup-verify" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
    BACKUP_DEST="${cfg.local.mountPoint}"
    BACKUP_ROOT="$BACKUP_DEST/$HOSTNAME"

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                     BACKUP VERIFICATION                            ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Check if latest backup exists
    if [[ ! -L "$BACKUP_ROOT/latest" ]]; then
      echo "✗ No latest backup found"
      exit 1
    fi

    LATEST_BACKUP=$(${pkgs.coreutils}/bin/readlink -f "$BACKUP_ROOT/latest")
    echo "Verifying backup: $LATEST_BACKUP"
    echo ""

    # Check each source directory
    ERRORS=0
    ${lib.concatMapStringsSep "\n" (source: ''
      echo "Checking ${source}..."

      if [[ -d "${source}" && -d "$LATEST_BACKUP${source}" ]]; then
        # Compare file counts
        ORIG_COUNT=$(${pkgs.findutils}/bin/find "${source}" -type f 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
        BACKUP_COUNT=$(${pkgs.findutils}/bin/find "$LATEST_BACKUP${source}" -type f 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)

        echo "  Original files: $ORIG_COUNT"
        echo "  Backup files:   $BACKUP_COUNT"

        if [[ "$ORIG_COUNT" -eq "$BACKUP_COUNT" ]]; then
          echo "  ✓ File count matches"
        else
          echo "  ⚠ File count mismatch (may be due to exclusions)"
        fi
      else
        echo "  ✗ Directory missing in backup"
        ERRORS=$((ERRORS + 1))
      fi
      echo ""
    '') cfg.local.sources}

    # Summary
    if [[ $ERRORS -eq 0 ]]; then
      echo "✓ Backup verification completed successfully"
      exit 0
    else
      echo "✗ Backup verification found $ERRORS error(s)"
      exit 1
    fi
  '';

in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      backupStatusScript
      backupNowScript
    ] ++ lib.optionals cfg.local.enable [
      restoreScript
      verifyBackupScript
    ];
  };
}
