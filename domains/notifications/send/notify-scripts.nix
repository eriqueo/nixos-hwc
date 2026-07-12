# domains/notifications/send/notify-scripts.nix
#
# Event-shaped notifiers for smartd, systemd OnFailure=, and backups.
# Each reads its trigger's context and delegates to the ONE command
# surface — `hwc-alert` — which POSTs to the hwc-notify dispatcher. No
# script here talks to Slack/gotify/n8n; they are thin adapters over the
# CLI, so routing/fan-out/audit live in exactly one place.
#
# Replaces the former slack-webhook.nix (webhookSender + these three).
# The script *names* (hwc-smartd-notify / hwc-service-failure-notify /
# hwc-backup-notify) are unchanged so their callers in
# domains/monitoring/alerts and domains/data/backup need no edits.

{ pkgs, lib, config }:

let
  # hwc-alert package (front-end onto :11600/notify).
  cliTool = import ./cli.nix { inherit pkgs lib config; };
  alert = "${cliTool}/bin/hwc-alert";
  logDir = "/var/log/hwc/notifications";

  smartdNotify = pkgs.writeShellApplication {
    name = "hwc-smartd-notify";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      LOG_FILE="${logDir}/smartd.log"
      mkdir -p "${logDir}"
      log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

      # smartd populates SMARTD_* in the environment when it runs the mailer.
      DEVICE="''${SMARTD_DEVICE:-unknown}"
      FAILTYPE="''${SMARTD_FAILTYPE:-unknown}"
      MESSAGE="''${SMARTD_MESSAGE:-No message}"

      log "SMART alert: $DEVICE - $FAILTYPE"

      case "$FAILTYPE" in
        CurrentPendingSector|ReallocatedSectorCt|OfflineUncorrectable) SEVERITY="critical" ;;
        *) SEVERITY="warning" ;;
      esac

      ${alert} "Disk Alert: $DEVICE" "$MESSAGE" \
        -s "$SEVERITY" -e smartd \
        -f "device=$DEVICE" -f "failure_type=$FAILTYPE" \
        -f "first_occurrence=''${SMARTD_TFIRST:-}" \
        || log "  WARNING: hwc-alert failed, logged locally only"
    '';
  };

  serviceFailureNotify = pkgs.writeShellApplication {
    name = "hwc-service-failure-notify";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd pkgs.util-linux ];
    text = ''
      set -euo pipefail
      LOG_FILE="${logDir}/service-failures.log"
      mkdir -p "${logDir}"
      log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

      # Called by systemd OnFailure= with the failed unit as %I.
      SERVICE_NAME="''${1:-unknown}"
      SERVICE_NAME="''${SERVICE_NAME%.service}"
      log "Service failure: $SERVICE_NAME"

      # A short recent-log snippet for the notification body — captured NOW,
      # before the grace sleep, so it shows the state at failure time.
      LOGS=$(journalctl -u "$SERVICE_NAME" -n 12 --no-pager 2>&1 | tail -12 || echo "Could not get logs")

      # Outcome-aware severity (2026-07-12 alert audit): most OnFailure hits
      # are stop artifacts of an orchestrated restart (the gluetun self-heal
      # SIGKILLs qbittorrent and segfaults mousehole on the way down) or
      # crashes that Restart= heals in seconds. Those used to page P1
      # (discord + email fan-out). Give the unit a grace window; only a unit
      # that is STILL not active gets the critical page — a recovered one
      # sends a warning-level note instead.
      sleep 30
      STATE=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
      if [ "$STATE" = "active" ] || [ "$STATE" = "activating" ]; then
        log "  recovered within grace window (state: $STATE) — warning, not page"
        ${alert} "Service crashed & auto-recovered: $SERVICE_NAME" \
          "Service $SERVICE_NAME failed but is $STATE again (self-healed within 30s). No action needed unless it recurs. Logs at failure:"$'\n'"$LOGS" \
          -s warning -e services \
          -f "service=$SERVICE_NAME" -f "recovered=true" \
          || log "  WARNING: hwc-alert failed, logged locally only"
      else
        ${alert} "Service Failed: $SERVICE_NAME" \
          "Service $SERVICE_NAME failed and is still $STATE. Act: journalctl -u $SERVICE_NAME -n 50, then systemctl restart $SERVICE_NAME. Recent logs:"$'\n'"$LOGS" \
          -s critical -e services \
          -f "service=$SERVICE_NAME" \
          || {
            log "  WARNING: hwc-alert failed; wall fallback"
            echo "SERVICE FAILURE: $SERVICE_NAME - check journalctl -u $SERVICE_NAME" | wall 2>/dev/null || true
          }
      fi
    '';
  };

  backupNotify = pkgs.writeShellApplication {
    name = "hwc-backup-notify";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux ];
    text = ''
      set -euo pipefail
      LOG_FILE="${logDir}/backup.log"
      mkdir -p "${logDir}"
      log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

      # Usage: hwc-backup-notify <success|failure> <backup_type> [details]
      STATUS="''${1:-unknown}"
      BACKUP_TYPE="''${2:-general}"
      DETAILS="''${3:-No details}"
      log "Backup: $BACKUP_TYPE - $STATUS"

      if [ "$STATUS" = "success" ]; then
        ${alert} "Backup Succeeded: $BACKUP_TYPE" "$BACKUP_TYPE backup completed successfully. $DETAILS" \
          -s info -e backup -f "backup_type=$BACKUP_TYPE" -f "status=success" \
          || log "  WARNING: hwc-alert failed, logged locally only"
      else
        ${alert} "Backup Failed: $BACKUP_TYPE" "$BACKUP_TYPE backup failed: $DETAILS" \
          -s critical -e backup -f "backup_type=$BACKUP_TYPE" -f "status=failure" \
          || {
            log "  WARNING: hwc-alert failed; wall fallback"
            echo "BACKUP FAILED: $BACKUP_TYPE - $DETAILS" | wall 2>/dev/null || true
          }
      fi
    '';
  };

in
{
  inherit smartdNotify serviceFailureNotify backupNotify;
}
