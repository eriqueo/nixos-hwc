# domains/system/services/backup/parts/cloud-backup.nix
# Cloud backup implementation using rclone (Proton Drive support)
# Supports sync, copy, and move modes with bandwidth limiting

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

  # Build exclude arguments for rclone
  excludeArgs = lib.concatMapStringsSep " " (pattern: "--exclude='${pattern}'") cfg.local.excludePatterns;

  # Build rclone flags
  rcloneFlags = lib.concatStringsSep " " (
    [ "--progress" "--transfers=4" "--checkers=8" ] ++
    (lib.optional (cfg.cloud.bandwidthLimit != null) "--bwlimit=${cfg.cloud.bandwidthLimit}") ++
    (lib.optional (cfg.cloud.syncMode == "sync") "--delete-during")
  );

  # Rclone config path
  rcloneConfig = if cfg.protonDrive.enable
    then "/etc/rclone-proton.conf"
    else "/root/.config/rclone/rclone.conf";

  # Cloud backup script using rclone
  cloudBackupScript = pkgs.writeScriptBin "backup-cloud" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Configuration
    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"
    REMOTE="${cfg.cloud.provider}:${cfg.cloud.remotePath}/$HOSTNAME"
    RCLONE_CONFIG="${rcloneConfig}"
    LOG_DIR="${cfg.monitoring.logPath}"
    LOG_FILE="$LOG_DIR/backup-cloud.log"

    # Logging functions
    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    log_error() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE" >&2
    }

    # Ensure log directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log "=== Cloud Backup Started ==="
    log "Hostname: $HOSTNAME"
    log "Remote: $REMOTE"
    log "Mode: ${cfg.cloud.syncMode}"

    # Check if rclone config exists
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
      log_error "Rclone config not found at $RCLONE_CONFIG"
      log_error "Please configure rclone first"
      exit 1
    fi

    # Test cloud connection
    log "Testing cloud connection..."
    if ! ${pkgs.rclone}/bin/rclone --config="$RCLONE_CONFIG" lsd "${cfg.cloud.provider}:" >/dev/null 2>&1; then
      log_error "Cannot connect to ${cfg.cloud.provider}"
      exit 1
    fi

    log "Cloud connection verified"

    # Run pre-backup script if configured
    ${lib.optionalString (cfg.preBackupScript != null) ''
      log "Running pre-backup script..."
      ${cfg.preBackupScript}
    ''}

    # Perform cloud backup for each source
    BACKUP_SUCCESS=true
    ${lib.concatMapStringsSep "\n" (source: ''
      if [[ -d "${source}" ]]; then
        log "Syncing ${source} to cloud..."

        if ${pkgs.rclone}/bin/rclone ${cfg.cloud.syncMode} \
          --config="$RCLONE_CONFIG" \
          ${rcloneFlags} \
          ${excludeArgs} \
          --log-file="$LOG_FILE" \
          --log-level=INFO \
          "${source}/" \
          "$REMOTE${source}/"; then
          log "✓ Successfully synced ${source}"
        else
          log_error "✗ Failed to sync ${source}"
          BACKUP_SUCCESS=false
        fi
      else
        log_error "Source directory ${source} does not exist, skipping"
      fi
    '') cfg.local.sources}

    if [[ "$BACKUP_SUCCESS" == true ]]; then
      log "Cloud backup completed successfully"

      # Get backup statistics from rclone
      log "Retrieving backup statistics..."
      ${pkgs.rclone}/bin/rclone size --config="$RCLONE_CONFIG" "$REMOTE" >> "$LOG_FILE" 2>&1 || true

      # Run post-backup script if configured
      ${lib.optionalString (cfg.postBackupScript != null) ''
        log "Running post-backup script..."
        ${cfg.postBackupScript}
      ''}

      # Send success notification
      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onSuccess) ''
        ${pkgs.libnotify}/bin/notify-send "Cloud Backup Complete" "Cloud backup to ${cfg.cloud.provider} completed successfully" --urgency=normal
      ''}

      log "=== Cloud Backup Completed Successfully ==="
      exit 0
    else
      log_error "=== Cloud Backup Failed ==="

      # Send failure notification
      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onFailure) ''
        ${pkgs.libnotify}/bin/notify-send "Cloud Backup Failed" "Cloud backup encountered errors. Check logs: $LOG_FILE" --urgency=critical
      ''}

      exit 1
    fi
  '';

in
{
  config = lib.mkIf (cfg.enable && cfg.cloud.enable) {
    # Install the cloud backup script
    environment.systemPackages = [ cloudBackupScript ];

    # Create log directory
    systemd.tmpfiles.rules = [
      "d ${cfg.monitoring.logPath} 0755 root root -"
    ];

    # Configure Proton Drive if enabled
    environment.etc."rclone-proton.conf" = lib.mkIf cfg.protonDrive.enable {
      source = config.age.secrets.${cfg.protonDrive.secretName}.path;
      mode = "0600";
    };

    # Systemd service for cloud backup
    systemd.services.backup-cloud = {
      description = "Cloud backup service (Proton Drive/rclone)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      unitConfig = lib.optionalAttrs cfg.schedule.onlyOnAC {
        # Only run on AC power for laptops (must be in [Unit])
        ConditionACPower = true;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cloudBackupScript}/bin/backup-cloud";
        User = "root";

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Timeout after 6 hours (cloud can be slow)
        TimeoutSec = "6h";
      };

      # Only start on-demand if scheduling is disabled
      wantedBy = lib.mkIf (!cfg.schedule.enable) [ "multi-user.target" ];
    };

    # Log rotation
    services.logrotate.settings.backup-cloud = {
      files = [ "${cfg.monitoring.logPath}/backup-cloud.log" ];
      frequency = "weekly";
      rotate = 8;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "0644 root root";
    };

    # Validation assertions
    assertions = [
      {
        assertion = !cfg.protonDrive.enable || (config.age.secrets ? "${cfg.protonDrive.secretName}");
        message = "Proton Drive is enabled, but the secret '${cfg.protonDrive.secretName}' was not found.";
      }
    ];
  };
}
