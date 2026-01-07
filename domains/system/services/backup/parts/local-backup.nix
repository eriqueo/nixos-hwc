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
    KEEP_DAILY=${toString cfg.local.keepDaily}
    KEEP_WEEKLY=${toString cfg.local.keepWeekly}
    KEEP_MONTHLY=${toString cfg.local.keepMonthly}

    # Logging functions
    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    log_error() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE" >&2
    }

    # Helpers
    is_complete() {
      [[ -f "$1/.BACKUP_COMPLETE" ]]
    }

    # Remove incomplete backups before any work
    prune_incomplete() {
      for type_dir in daily weekly monthly; do
        local base="$BACKUP_ROOT/$type_dir"
        [[ -d "$base" ]] || continue
        for incomplete in $(${pkgs.findutils}/bin/find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
          if [[ -d "$incomplete" ]] && ! is_complete "$incomplete"; then
            log "Removing incomplete backup: $incomplete"
            ${pkgs.coreutils}/bin/rm -rf "$incomplete"
          fi
        done
      done
    }

    # Prune backups by count (oldest first), keeping only the newest N complete snapshots
    prune_by_count() {
      local type_dir="$1"
      local keep="$2"
      [[ "$keep" -le 0 ]] && return 0
      local base="$BACKUP_ROOT/$type_dir"
      [[ -d "$base" ]] || return 0

      mapfile -t backups < <(${pkgs.findutils}/bin/find "$base" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | ${pkgs.coreutils}/bin/sort)

      # Filter to completed backups only
      local completed=()
      for b in ''${backups[@]}; do
        if is_complete "$b"; then
          completed+=("$b")
        fi
      done

      local count=''${#completed[@]}
      if (( count > keep )); then
        local to_delete=$((count - keep))
        for ((i = 0; i < to_delete; i++)); do
          local target="''${completed[$i]}"
          log "Removing old ''${type_dir%/} backup: $(${pkgs.coreutils}/bin/basename "$target")"
          ${pkgs.coreutils}/bin/rm -rf "$target"
        done
      fi
    }

    prune_retention() {
      prune_by_count daily "$KEEP_DAILY"
      prune_by_count weekly "$KEEP_WEEKLY"
      prune_by_count monthly "$KEEP_MONTHLY"
    }

    # Last-resort pruning: remove oldest backups (preserve at least one per tier) until space meets threshold
    emergency_prune_for_space() {
      while true; do
        AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')
        (( AVAILABLE_GB >= ${toString cfg.local.minSpaceGB} )) && return 0

        local removed=false
        for type_dir in daily weekly monthly; do
          local base="$BACKUP_ROOT/$type_dir"
          [[ -d "$base" ]] || continue
          mapfile -t backups < <(${pkgs.findutils}/bin/find "$base" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | ${pkgs.coreutils}/bin/sort)
          # Keep at least one backup per tier
          if (( ''${#backups[@]} > 1 )); then
            local target="''${backups[0]}"
            log "Emergency pruning $type_dir backup to free space: $(${pkgs.coreutils}/bin/basename "$target")"
            ${pkgs.coreutils}/bin/rm -rf "$target"
            removed=true
            break
          fi
        done

        if [[ "$removed" == false ]]; then
          return 1
        fi
      done
    }

    # Ensure log directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log "=== Local Backup Started ==="
    log "Hostname: $HOSTNAME"
    log "Destination: $BACKUP_DEST"

    # Acquire exclusive lock to prevent concurrent backups
    LOCK_FILE="$BACKUP_DEST/.backup.lock"
    LOCK_FD=200
    eval "exec $LOCK_FD>$LOCK_FILE"

    if ! ${pkgs.util-linux}/bin/flock -n $LOCK_FD; then
      log_error "Another backup is already running (lock file: $LOCK_FILE)"
      exit 1
    fi

    log "✓ Acquired backup lock"

    # Ensure lock is released on exit
    trap "${pkgs.util-linux}/bin/flock -u $LOCK_FD" EXIT

    # Check if destination is mounted
    if [[ ! -d "$BACKUP_DEST" ]]; then
      log_error "Backup destination $BACKUP_DEST does not exist"
      exit 1
    fi

    if ! ${pkgs.util-linux}/bin/mountpoint -q "$BACKUP_DEST"; then
      log_error "Backup destination $BACKUP_DEST is not mounted"
      exit 1
    fi

    # Cleanup stale/incomplete backups before space check
    prune_incomplete
    prune_retention

    # Check available space after pruning
    AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')
    if [[ "$AVAILABLE_GB" -lt ${toString cfg.local.minSpaceGB} ]]; then
      log "Low space ($AVAILABLE_GB GB). Attempting emergency pruning to reach ${toString cfg.local.minSpaceGB} GB..."
      if ! emergency_prune_for_space; then
        AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')
        log_error "Insufficient space after pruning: $AVAILABLE_GB GB available, need ${toString cfg.local.minSpaceGB} GB"
        exit 1
      fi
      AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "$BACKUP_DEST" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')
    fi

    log "Available space: $AVAILABLE_GB GB"

    # Create backup directories
    ${pkgs.coreutils}/bin/mkdir -p "$BACKUP_ROOT"/{daily,weekly,monthly}

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

    # Create backup in temporary directory first for atomicity
    BACKUP_DIR_TEMP="$BACKUP_ROOT/.in-progress/$DATE"
    BACKUP_DIR_FINAL="$BACKUP_ROOT/$BACKUP_TYPE/$DATE"

    log "Temporary directory: $BACKUP_DIR_TEMP"
    log "Final directory: $BACKUP_DIR_FINAL"

    # Clean any stale in-progress backups
    ${pkgs.coreutils}/bin/rm -rf "$BACKUP_ROOT/.in-progress"
    ${pkgs.coreutils}/bin/mkdir -p "$BACKUP_ROOT/.in-progress"

    # Run pre-backup script if configured
    ${lib.optionalString (cfg.preBackupScript != null) ''
      log "Running pre-backup script..."
      ${cfg.preBackupScript}
    ''}

    # Perform rsync backup for each source
    BACKUP_SUCCESS=true
    ${lib.concatMapStringsSep "\n" (source: ''
      if [[ -d "${source}" ]]; then
        # Create parent directory structure in temp location
        SOURCE_PARENT="$BACKUP_DIR_TEMP$(dirname "${source}")"
        ${pkgs.coreutils}/bin/mkdir -p "$SOURCE_PARENT"
        log "Backing up ${source}..."

        if ${pkgs.rsync}/bin/rsync -aAXHv \
          --delete \
          --delete-excluded \
          ${excludeArgs} \
          ${lib.optionalString (cfg.local.useRsync) "--link-dest=$BACKUP_ROOT/latest"} \
          "${source}/" \
          "$BACKUP_DIR_TEMP${source}/" \
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
      # Create completion marker for atomic snapshot detection
      log "Creating backup completion marker..."
      cat > "$BACKUP_DIR_TEMP/.BACKUP_COMPLETE" << EOF
backup_date=$DATE
backup_type=$BACKUP_TYPE
hostname=$HOSTNAME
completed_at=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)
backup_version=1.0
EOF

      # Atomically move temp backup to final location
      log "Atomically publishing backup snapshot..."
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$BACKUP_DIR_FINAL")"
      ${pkgs.coreutils}/bin/mv "$BACKUP_DIR_TEMP" "$BACKUP_DIR_FINAL"

      # Update 'latest' symlink atomically
      LATEST_TMP="$BACKUP_ROOT/.latest.tmp"
      ${pkgs.coreutils}/bin/ln -sf "$BACKUP_DIR_FINAL" "$LATEST_TMP"
      ${pkgs.coreutils}/bin/mv -f "$LATEST_TMP" "$BACKUP_ROOT/latest"

      log "✓ Backup snapshot published atomically"

      # Clean old backups (only complete ones)
      log "Cleaning old backups..."
      prune_incomplete
      prune_retention
      log "Cleanup completed (count-based retention)"

      # Calculate backup statistics
      BACKUP_SIZE=$(${pkgs.coreutils}/bin/du -sh "$BACKUP_DIR_FINAL" | ${pkgs.coreutils}/bin/cut -f1)
      TOTAL_BACKUPS=$(${pkgs.findutils}/bin/find "$BACKUP_ROOT"/{daily,weekly,monthly} -maxdepth 1 -type d -name "*_*" | ${pkgs.coreutils}/bin/wc -l)

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

      # Never auto-start at boot; only via timer, coordinator, or manual invocation
      # This prevents the backup from running during system activation/rebuild
      wantedBy = [ ];
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
