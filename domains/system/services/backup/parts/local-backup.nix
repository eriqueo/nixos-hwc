# domains/system/services/backup/parts/local-backup.nix
# Local backup implementation using rsync for incremental backups
# Supports external drives, NAS, and DAS with rotating snapshots

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

  # Build exclude arguments for rsync
  excludeArgs = lib.concatMapStringsSep " " (pattern: "--exclude='${pattern}'") cfg.local.excludePatterns;

  # Local backup script using rsync with hard-link snapshots
  localBackupScript = pkgs.writeScriptBin "backup-local" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Configuration
    BACKUP_DEST="${cfg.local.mountPoint}"
    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
    BACKUP_ROOT="$BACKUP_DEST/$HOSTNAME"
    DATE=$(${pkgs.coreutils}/bin/date +%Y-%m-%d)
    DAY_OF_WEEK=$(${pkgs.coreutils}/bin/date +%u)  # 1=Monday, 7=Sunday
    DAY_OF_MONTH=$(${pkgs.coreutils}/bin/date +%d)
    LOG_DIR="${cfg.monitoring.logPath}"
    LOG_FILE="$LOG_DIR/backup-local.log"

    # Logging functions
    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    log_error() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE" >&2
    }

    # Ensure log directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log "=== Local Backup Started ==="
    log "Hostname: $HOSTNAME"
    log "Destination: $BACKUP_DEST"

    # Check if destination is mounted
    if [[ ! -d "$BACKUP_DEST" ]]; then
      log_error "Backup destination $BACKUP_DEST does not exist"
      exit 1
    fi

    if ! ${pkgs.util-linux}/bin/mountpoint -q "$BACKUP_DEST"; then
      log_error "Backup destination $BACKUP_DEST is not mounted"
      exit 1
    fi

    # Check available space
    AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')
    if [[ "$AVAILABLE_GB" -lt ${toString cfg.local.minSpaceGB} ]]; then
      log_error "Insufficient space: $AVAILABLE_GB GB available, need ${toString cfg.local.minSpaceGB} GB"
      exit 1
    fi

    log "Available space: $AVAILABLE_GB GB"

    # Create backup directories
    ${pkgs.coreutils}/bin/mkdir -p "$BACKUP_ROOT"/{daily,weekly,monthly,latest}

    # Determine backup type based on day
    BACKUP_TYPE="daily"
    BACKUP_DIR="$BACKUP_ROOT/daily/$DATE"

    # Weekly backup on Sunday (day 7)
    if [[ "$DAY_OF_WEEK" -eq 7 ]]; then
      BACKUP_TYPE="weekly"
      BACKUP_DIR="$BACKUP_ROOT/weekly/$DATE"
    fi

    # Monthly backup on the 1st
    if [[ "$DAY_OF_MONTH" -eq 1 ]]; then
      BACKUP_TYPE="monthly"
      BACKUP_DIR="$BACKUP_ROOT/monthly/$DATE"
    fi

    # Ensure the concrete backup directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$BACKUP_DIR"

    log "Backup type: $BACKUP_TYPE"
    log "Backup directory: $BACKUP_DIR"

    # Run pre-backup script if configured
    ${lib.optionalString (cfg.preBackupScript != null) ''
      log "Running pre-backup script..."
      ${cfg.preBackupScript}
    ''}

    # Perform rsync backup for each source
    BACKUP_SUCCESS=true
    ${lib.concatMapStringsSep "\n" (source: ''
      if [[ -d "${source}" ]]; then
        # Create parent directory structure
        SOURCE_PARENT="$BACKUP_DIR$(dirname "${source}")"
        ${pkgs.coreutils}/bin/mkdir -p "$SOURCE_PARENT"
        log "Backing up ${source}..."

        if ${pkgs.rsync}/bin/rsync -aAXHv \
          --delete \
          --delete-excluded \
          ${excludeArgs} \
          ${lib.optionalString (cfg.local.useRsync) "--link-dest=$BACKUP_ROOT/latest"} \
          "${source}/" \
          "$BACKUP_DIR${source}/" \
          >> "$LOG_FILE" 2>&1; then
          log "✓ Successfully backed up ${source}"
        else
          log_error "✗ Failed to backup ${source}"
          BACKUP_SUCCESS=false
        fi
      else
        log_error "Source directory ${source} does not exist, skipping"
      fi
    '') cfg.local.sources}

    if [[ "$BACKUP_SUCCESS" == true ]]; then
      # Update 'latest' symlink
      ${pkgs.coreutils}/bin/rm -f "$BACKUP_ROOT/latest"
      ${pkgs.coreutils}/bin/ln -s "$BACKUP_DIR" "$BACKUP_ROOT/latest"

      log "Backup completed successfully"

      # Clean old backups
      log "Cleaning old backups..."

      # Keep only last N daily backups
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/daily" -maxdepth 1 -type d -mtime +${toString cfg.local.keepDaily} -exec rm -rf {} \; 2>/dev/null || true

      # Keep only last N weekly backups
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/weekly" -maxdepth 1 -type d -mtime +$((${toString cfg.local.keepWeekly} * 7)) -exec rm -rf {} \; 2>/dev/null || true

      # Keep only last N monthly backups
      ${pkgs.findutils}/bin/find "$BACKUP_ROOT/monthly" -maxdepth 1 -type d -mtime +$((${toString cfg.local.keepMonthly} * 30)) -exec rm -rf {} \; 2>/dev/null || true

      log "Cleanup completed"

      # Calculate backup statistics
      BACKUP_SIZE=$(${pkgs.coreutils}/bin/du -sh "$BACKUP_DIR" | ${pkgs.coreutils}/bin/cut -f1)
      TOTAL_BACKUPS=$(${pkgs.findutils}/bin/find "$BACKUP_ROOT"/{daily,weekly,monthly} -maxdepth 1 -type d | ${pkgs.coreutils}/bin/wc -l)

      log "Backup size: $BACKUP_SIZE"
      log "Total backups on disk: $TOTAL_BACKUPS"

      # Run post-backup script if configured
      ${lib.optionalString (cfg.postBackupScript != null) ''
        log "Running post-backup script..."
        ${cfg.postBackupScript}
      ''}

      # Send success notification (desktop)
      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onSuccess) ''
        ${pkgs.libnotify}/bin/notify-send "Backup Complete" "Local backup completed successfully ($BACKUP_SIZE)" --urgency=normal
      ''}

      # Send success notification (ntfy)
      ${lib.optionalString (config.hwc.system.services.ntfy.enable or false && cfg.notifications.ntfy.enable && cfg.notifications.ntfy.onSuccess) ''
        NTFY_TOPIC="${if cfg.notifications.ntfy.topic != null then cfg.notifications.ntfy.topic else "-"}"
        hwc-ntfy-send --tag backup,success --priority 3 \
          "$NTFY_TOPIC" \
          "[$HOSTNAME] Backup Success" \
          "Local backup completed successfully.
Type: $BACKUP_TYPE
Size: $BACKUP_SIZE
Total backups: $TOTAL_BACKUPS
Log: $LOG_FILE" || log "Warning: Failed to send ntfy notification"
      ''}

      log "=== Local Backup Completed Successfully ==="
      exit 0
    else
      log_error "=== Backup Failed ==="

      # Send failure notification (desktop)
      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onFailure) ''
        ${pkgs.libnotify}/bin/notify-send "Backup Failed" "Local backup encountered errors. Check logs: $LOG_FILE" --urgency=critical
      ''}

      # Send failure notification (ntfy)
      ${lib.optionalString (config.hwc.system.services.ntfy.enable or false && cfg.notifications.ntfy.enable && cfg.notifications.ntfy.onFailure) ''
        NTFY_TOPIC="${if cfg.notifications.ntfy.topic != null then cfg.notifications.ntfy.topic else "-"}"
        hwc-ntfy-send --tag backup,failure,urgent --priority 5 \
          "$NTFY_TOPIC" \
          "[$HOSTNAME] Backup FAILED" \
          "Local backup encountered errors!
Type: $BACKUP_TYPE
Hostname: $HOSTNAME
Destination: $BACKUP_DEST
Log: $LOG_FILE

Check the logs for details." || log_error "Warning: Failed to send ntfy notification"
      ''}

      exit 1
    fi
  '';

in
{
  config = lib.mkIf (cfg.enable && cfg.local.enable) {
    # Install the local backup script
    environment.systemPackages = [ localBackupScript ];

    # Create log directory
    systemd.tmpfiles.rules = [
      "d ${cfg.monitoring.logPath} 0755 root root -"
    ];

    # Systemd service for local backup
    systemd.services.backup-local = {
      description = "Local backup service (external drive/NAS/DAS)";
      after = [ "local-fs.target" ];
      wants = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${localBackupScript}/bin/backup-local";
        User = "root";

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Timeout after 4 hours
        TimeoutSec = "4h";
      };

      # Only start on-demand if scheduling is disabled
      wantedBy = lib.mkIf (!cfg.schedule.enable) [ "multi-user.target" ];
    };

    # Log rotation
    services.logrotate.settings.backup-local = {
      files = [ "${cfg.monitoring.logPath}/backup-local.log" ];
      frequency = "weekly";
      rotate = 8;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "0644 root root";
    };
  };
}
