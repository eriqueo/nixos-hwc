# domains/system/services/backup/parts/backup-scheduler.nix
# Backup scheduling using systemd timers
# Coordinates local and cloud backups based on configuration

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

	mkOnCalendar = { frequency, timeOfDay }:
	    if frequency == "daily" then
	      "*-*-* ${timeOfDay}:00"
	    else if frequency == "weekly" then
	      "Mon *-*-* ${timeOfDay}:00"
	    else
	      "${frequency} ${timeOfDay}:00";
	      
  # Main backup coordination script
  backupCoordinatorScript = pkgs.writeScriptBin "backup-coordinator" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${cfg.monitoring.logPath}"
    LOG_FILE="$LOG_DIR/backup-coordinator.log"

    # Logging function
    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Ensure log directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log "=== Backup Coordinator Started ==="

    SUCCESS=true

    # Run local backup if enabled
    ${lib.optionalString cfg.local.enable ''
      log "Starting local backup..."
      if ${pkgs.systemd}/bin/systemctl start backup-local.service; then
        ${pkgs.systemd}/bin/systemctl --no-pager status backup-local.service >> "$LOG_FILE" 2>&1 || true
        log "✓ Local backup completed"
      else
        log "✗ Local backup failed"
        SUCCESS=false
      fi
    ''}

    # Run cloud backup if enabled (can run in parallel or as fallback)
    ${lib.optionalString cfg.cloud.enable ''
      log "Starting cloud backup..."
      if ${pkgs.systemd}/bin/systemctl start backup-cloud.service; then
        ${pkgs.systemd}/bin/systemctl --no-pager status backup-cloud.service >> "$LOG_FILE" 2>&1 || true
        log "✓ Cloud backup completed"
      else
        log "✗ Cloud backup failed"
        SUCCESS=false
      fi
    ''}

    # Summary
    if [[ "$SUCCESS" == true ]]; then
      log "=== All Backups Completed Successfully ==="

      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onSuccess) ''
        ${pkgs.libnotify}/bin/notify-send "Backup Complete" "All scheduled backups completed successfully" --urgency=normal
      ''}

      exit 0
    else
      log "=== Some Backups Failed ==="

      ${lib.optionalString (cfg.notifications.enable && cfg.notifications.onFailure) ''
        ${pkgs.libnotify}/bin/notify-send "Backup Failed" "Some backups encountered errors. Check logs: $LOG_FILE" --urgency=critical
      ''}

      exit 1
    fi
  '';

in
{
  config = lib.mkIf (cfg.enable && cfg.schedule.enable) {
    # Create log directory
    systemd.tmpfiles.rules = [
      "d ${cfg.monitoring.logPath} 0755 root root -"
    ];

    # Main backup service that coordinates all backups
    systemd.services.backup = {
      description = "Coordinated backup service (local + cloud)";
      wants = lib.optionals cfg.cloud.enable [ "network-online.target" ];
      after = [ "local-fs.target" ] ++ lib.optionals cfg.cloud.enable [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupCoordinatorScript}/bin/backup-coordinator";
        User = "root";

        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Timeout after 8 hours (generous for large backups)
        TimeoutSec = "8h";

        # Nice level for background operation
        Nice = 10;
        IOSchedulingClass = "idle";
      } // lib.optionalAttrs cfg.schedule.onlyOnAC {
        # Only run on AC power for laptops
        ConditionACPower = true;
      };
    };

    # Backup timer for scheduled execution
    systemd.timers.backup = {
      description = "Automated backup timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        # Combine frequency with time of day
        OnCalendar = mkOnCalendar {
                  frequency = cfg.schedule.frequency;
                  timeOfDay = cfg.schedule.timeOfDay;
                };

        # Random delay to avoid thundering herd
        RandomizedDelaySec = cfg.schedule.randomDelay;
                Persistent = true;
                AccuracySec = "1h";
   
      };
    };

    # Log rotation for coordinator
    services.logrotate.settings.backup-coordinator = {
      files = [ "${cfg.monitoring.logPath}/backup-coordinator.log" ];
      frequency = "weekly";
      rotate = 8;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "0644 root root";
    };

    # Health check service (monitors backup health)
    systemd.services.backup-health-check = lib.mkIf cfg.monitoring.enable {
      description = "Backup health check service";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeScript "backup-health-check" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          LOG_DIR="${cfg.monitoring.logPath}"
          LOG_FILE="$LOG_DIR/backup-health.log"

          log() {
            echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
          }

          ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

          log "=== Backup Health Check Started ==="

          # Check for recent successful backups
          ${lib.optionalString cfg.local.enable ''
            if [[ -f "$LOG_DIR/backup-local.log" ]]; then
              LAST_SUCCESS=$(${pkgs.gnugrep}/bin/grep "Backup Completed Successfully" "$LOG_DIR/backup-local.log" | ${pkgs.coreutils}/bin/tail -n1 || echo "")

              if [[ -n "$LAST_SUCCESS" ]]; then
                log "✓ Local backup: Last success found"
              else
                log "⚠ Local backup: No successful backup found in logs"
              fi
            fi
          ''}

          ${lib.optionalString cfg.cloud.enable ''
            if [[ -f "$LOG_DIR/backup-cloud.log" ]]; then
              LAST_SUCCESS=$(${pkgs.gnugrep}/bin/grep "Backup Completed Successfully" "$LOG_DIR/backup-cloud.log" | ${pkgs.coreutils}/bin/tail -n1 || echo "")

              if [[ -n "$LAST_SUCCESS" ]]; then
                log "✓ Cloud backup: Last success found"
              else
                log "⚠ Cloud backup: No successful backup found in logs"
              fi
            fi
          ''}

          # Check disk space on backup destination
          ${lib.optionalString cfg.local.enable ''
            if ${pkgs.util-linux}/bin/mountpoint -q "${cfg.local.mountPoint}" 2>/dev/null; then
              AVAILABLE_GB=$(${pkgs.coreutils}/bin/df -BG "${cfg.local.mountPoint}" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}' | ${pkgs.gnused}/bin/sed 's/G//')

              if [[ "$AVAILABLE_GB" -lt ${toString cfg.local.minSpaceGB} ]]; then
                log "⚠ Low disk space on backup destination: $AVAILABLE_GB GB"
              else
                log "✓ Sufficient disk space: $AVAILABLE_GB GB"
              fi
            fi
          ''}

          log "=== Health Check Complete ==="
        ''}";
        User = "root";
      };
    };

    # Health check timer
    systemd.timers.backup-health-check = lib.mkIf cfg.monitoring.enable {
      description = "Backup health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.monitoring.healthCheckInterval;
        Persistent = true;
      };
    };
  };
}
