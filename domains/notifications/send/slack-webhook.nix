# domains/notifications/send/slack-webhook.nix
#
# Robust webhook scripts for alerts via n8n
# Features: retry logic, local logging fallback, health checks

{ pkgs, lib, config }:

let
  webhookCfg = config.hwc.notifications.webhook;
  severityCfg = config.hwc.monitoring.alerts.severity;
  diskSpaceCfg = config.hwc.monitoring.alerts.sources.diskSpace;

  # Build webhook URL for a given endpoint
  mkWebhookUrl = endpoint: "${webhookCfg.baseUrl}/${webhookCfg.endpoints.${endpoint}}";

  # Log directory
  logDir = "/var/log/hwc/notifications";

  # Generic webhook sender script with retry and fallback logging
  webhookSender = pkgs.writeScriptBin "hwc-webhook-send" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Usage: hwc-webhook-send <endpoint> <title> <message> [severity] [extra_fields_json]
    # endpoint: system, backup, smartd, services
    # severity: info, warning, critical (default: info)
    # extra_fields_json: optional JSON object to merge into payload

    ENDPOINT="''${1:-system}"
    TITLE="''${2:-Alert}"
    MESSAGE="''${3:-No message provided}"
    SEVERITY="''${4:-info}"
    EXTRA_FIELDS="''${5:-"{}"}"

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/webhook.log"
    FAILED_LOG="$LOG_DIR/failed-alerts.log"

    # Ensure log directory exists
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    # Logging function
    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Log failed alert for later review/retry
    log_failed() {
      local reason="$1"
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] FAILED ($reason): [$SEVERITY] $TITLE - $MESSAGE" >> "$FAILED_LOG"
      # Also write full payload for potential manual retry
      echo "  Endpoint: $ENDPOINT" >> "$FAILED_LOG"
      echo "  Payload: $PAYLOAD" >> "$FAILED_LOG"
      echo "---" >> "$FAILED_LOG"
    }

    # Map endpoint to URL
    case "$ENDPOINT" in
      system)
        URL="${mkWebhookUrl "system"}"
        ;;
      backup)
        URL="${mkWebhookUrl "backup"}"
        ;;
      smartd|disk)
        URL="${mkWebhookUrl "smartd"}"
        ;;
      services|service)
        URL="${mkWebhookUrl "services"}"
        ;;
      *)
        # Allow full URL to be passed
        if [[ "$ENDPOINT" == http* ]]; then
          URL="$ENDPOINT"
        else
          log "ERROR: Unknown endpoint: $ENDPOINT"
          exit 1
        fi
        ;;
    esac

    # Map severity to tag
    case "$SEVERITY" in
      critical)
        SEVERITY_TAG="${severityCfg.critical}"
        ;;
      warning)
        SEVERITY_TAG="${severityCfg.warning}"
        ;;
      *)
        SEVERITY_TAG="${severityCfg.info}"
        ;;
    esac

    # Build JSON payload
    TIMESTAMP=$(${pkgs.coreutils}/bin/date -Iseconds)
    HOSTNAME=$(${pkgs.nettools}/bin/hostname)

    PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      --arg title "$TITLE" \
      --arg message "$MESSAGE" \
      --arg severity "$SEVERITY" \
      --arg severity_tag "$SEVERITY_TAG" \
      --arg timestamp "$TIMESTAMP" \
      --arg hostname "$HOSTNAME" \
      --argjson extra "$EXTRA_FIELDS" \
      '{
        title: $title,
        message: $message,
        severity: $severity,
        severity_tag: $severity_tag,
        timestamp: $timestamp,
        hostname: $hostname
      } + $extra')

    log "Sending alert: [$SEVERITY] $TITLE"

    # Retry logic: 3 attempts with exponential backoff
    MAX_RETRIES=3
    RETRY_DELAY=2
    SUCCESS=false

    for attempt in $(seq 1 $MAX_RETRIES); do
      log "  Attempt $attempt/$MAX_RETRIES to $URL"

      # Use timeout to prevent hanging
      if RESPONSE=$(${pkgs.coreutils}/bin/timeout 30 ${pkgs.curl}/bin/curl -s -w "\n%{http_code}" -X POST "$URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>&1); then

        # Extract HTTP status code (last line)
        HTTP_CODE=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
        BODY=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/head -n -1)

        if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
          log "  Success (HTTP $HTTP_CODE)"
          SUCCESS=true
          break
        else
          log "  Failed: HTTP $HTTP_CODE - $BODY"
        fi
      else
        log "  Failed: curl error or timeout"
      fi

      if [ $attempt -lt $MAX_RETRIES ]; then
        log "  Retrying in $RETRY_DELAY seconds..."
        ${pkgs.coreutils}/bin/sleep $RETRY_DELAY
        RETRY_DELAY=$((RETRY_DELAY * 2))
      fi
    done

    if [ "$SUCCESS" = false ]; then
      log "ERROR: All $MAX_RETRIES attempts failed for: $TITLE"
      log_failed "webhook unreachable after $MAX_RETRIES attempts"

      # For critical alerts, also try wall message as last resort
      if [ "$SEVERITY" = "critical" ]; then
        log "  Sending wall message as fallback for critical alert"
        echo "CRITICAL ALERT: $TITLE - $MESSAGE" | ${pkgs.util-linux}/bin/wall 2>/dev/null || true
      fi

      exit 1
    fi

    echo "Alert sent: $TITLE ($SEVERITY)"
  '';

  # Health check script for n8n webhook endpoint
  webhookHealthCheck = pkgs.writeScriptBin "hwc-webhook-health" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/health.log"
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Check if n8n webhook base URL is reachable
    BASE_URL="${webhookCfg.baseUrl}"

    log "Checking webhook endpoint health: $BASE_URL"

    if ${pkgs.coreutils}/bin/timeout 10 ${pkgs.curl}/bin/curl -sf -o /dev/null "$BASE_URL" 2>/dev/null; then
      log "  Webhook endpoint is healthy"
      exit 0
    else
      log "  WARNING: Webhook endpoint unreachable"
      exit 1
    fi
  '';

  # SMART disk alert script (for smartd notifications)
  smartdNotify = pkgs.writeScriptBin "hwc-smartd-notify" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/smartd.log"
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Called by smartd with environment variables:
    # SMARTD_DEVICE - device path
    # SMARTD_DEVICETYPE - device type
    # SMARTD_DEVICESTRING - device string
    # SMARTD_FAILTYPE - failure type
    # SMARTD_MESSAGE - full message
    # SMARTD_TFIRST - time of first failure
    # SMARTD_TFIRSTEPOCH - epoch of first failure

    DEVICE="''${SMARTD_DEVICE:-unknown}"
    FAILTYPE="''${SMARTD_FAILTYPE:-unknown}"
    MESSAGE="''${SMARTD_MESSAGE:-No message}"

    log "SMART alert received: $DEVICE - $FAILTYPE"
    log "  Message: $MESSAGE"

    # Determine severity based on failure type
    case "$FAILTYPE" in
      CurrentPendingSector|ReallocatedSectorCt|OfflineUncorrectable)
        SEVERITY="critical"
        log "  Severity: CRITICAL (disk may be failing)"
        ;;
      *)
        SEVERITY="warning"
        log "  Severity: warning"
        ;;
    esac

    # Build extra fields
    EXTRA=$(${pkgs.jq}/bin/jq -n \
      --arg device "$DEVICE" \
      --arg failtype "$FAILTYPE" \
      --arg tfirst "''${SMARTD_TFIRST:-}" \
      '{
        device: $device,
        failure_type: $failtype,
        first_occurrence: $tfirst,
        source: "smartd"
      }')

    # Send webhook (with retry logic built into hwc-webhook-send)
    ${webhookSender}/bin/hwc-webhook-send \
      smartd \
      "Disk Alert: $DEVICE" \
      "$MESSAGE" \
      "$SEVERITY" \
      "$EXTRA" || {
        log "  WARNING: Failed to send webhook, alert logged locally"
      }
  '';

  # Service failure alert script
  serviceFailureNotify = pkgs.writeScriptBin "hwc-service-failure-notify" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/service-failures.log"
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Called by systemd OnFailure= with service name as argument
    SERVICE_NAME="''${1:-unknown}"

    # Remove .service suffix if present (systemd passes full unit name)
    SERVICE_NAME="''${SERVICE_NAME%.service}"

    log "Service failure detected: $SERVICE_NAME"

    # Get service status (may fail if service doesn't exist)
    STATUS=$(${pkgs.systemd}/bin/systemctl status "$SERVICE_NAME" 2>&1 | ${pkgs.coreutils}/bin/head -20 || echo "Could not get status")

    # Get recent logs
    LOGS=$(${pkgs.systemd}/bin/journalctl -u "$SERVICE_NAME" -n 15 --no-pager 2>&1 || echo "Could not get logs")

    log "  Status: $(echo "$STATUS" | ${pkgs.coreutils}/bin/head -3)"

    # Build extra fields
    EXTRA=$(${pkgs.jq}/bin/jq -n \
      --arg service "$SERVICE_NAME" \
      --arg status "$STATUS" \
      --arg logs "$LOGS" \
      '{
        service: $service,
        status: $status,
        recent_logs: $logs,
        source: "systemd"
      }')

    # Send webhook
    ${webhookSender}/bin/hwc-webhook-send \
      services \
      "Service Failed: $SERVICE_NAME" \
      "Service $SERVICE_NAME has failed. Check logs for details." \
      critical \
      "$EXTRA" || {
        log "  WARNING: Failed to send webhook, alert logged locally"
        # Critical service failures get wall message as fallback
        echo "SERVICE FAILURE: $SERVICE_NAME - Check journalctl -u $SERVICE_NAME" | ${pkgs.util-linux}/bin/wall 2>/dev/null || true
      }
  '';

  # Disk space check script
  diskSpaceCheck = pkgs.writeScriptBin "hwc-disk-space-check" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/disk-space.log"
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    CRITICAL_THRESHOLD="${toString diskSpaceCfg.criticalThreshold}"
    WARNING_THRESHOLD="${toString diskSpaceCfg.warningThreshold}"
    FILESYSTEMS="${lib.concatStringsSep " " diskSpaceCfg.filesystems}"

    log "Starting disk space check (warn: $WARNING_THRESHOLD%, crit: $CRITICAL_THRESHOLD%)"

    ALERTS_SENT=0
    ERRORS=0

    for FS in $FILESYSTEMS; do
      # Check if filesystem is mounted (with timeout for network mounts)
      if ! ${pkgs.coreutils}/bin/timeout 5 ${pkgs.util-linux}/bin/mountpoint -q "$FS" 2>/dev/null; then
        log "  Skipping $FS (not mounted or timeout)"
        continue
      fi

      # Get usage percentage (remove % sign)
      USAGE=$(${pkgs.coreutils}/bin/df -P "$FS" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $5}' | tr -d '%')

      if [ -z "$USAGE" ]; then
        log "  ERROR: Could not get usage for $FS"
        ERRORS=$((ERRORS + 1))
        continue
      fi

      log "  $FS: $USAGE%"

      # Determine severity
      SEVERITY="info"
      if [ "$USAGE" -ge "$CRITICAL_THRESHOLD" ]; then
        SEVERITY="critical"
      elif [ "$USAGE" -ge "$WARNING_THRESHOLD" ]; then
        SEVERITY="warning"
      fi

      # Only send alerts for warning or critical
      if [ "$SEVERITY" != "info" ]; then
        # Get more details
        AVAILABLE=$(${pkgs.coreutils}/bin/df -h "$FS" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}')
        TOTAL=$(${pkgs.coreutils}/bin/df -h "$FS" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $2}')

        log "    ALERT: $FS at $USAGE% ($AVAILABLE available of $TOTAL)"

        EXTRA=$(${pkgs.jq}/bin/jq -n \
          --arg filesystem "$FS" \
          --arg usage "$USAGE" \
          --arg available "$AVAILABLE" \
          --arg total "$TOTAL" \
          '{
            filesystem: $filesystem,
            usage_percent: $usage,
            available: $available,
            total: $total,
            source: "disk-monitor"
          }')

        if ${webhookSender}/bin/hwc-webhook-send \
          smartd \
          "Disk Space ''${SEVERITY^}: $FS at $USAGE%" \
          "Filesystem $FS is at $USAGE% capacity ($AVAILABLE available of $TOTAL)" \
          "$SEVERITY" \
          "$EXTRA"; then
          ALERTS_SENT=$((ALERTS_SENT + 1))
        else
          log "    WARNING: Failed to send alert for $FS"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done

    log "Disk space check complete: $ALERTS_SENT alerts sent, $ERRORS errors"

    # Exit with error if any errors occurred (for systemd to track)
    if [ "$ERRORS" -gt 0 ]; then
      exit 1
    fi
  '';

  # Backup notification script (to be called by backup-scheduler)
  backupNotify = pkgs.writeScriptBin "hwc-backup-notify" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/backup.log"
    ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    # Usage: hwc-backup-notify <success|failure> <backup_type> [details]
    STATUS="''${1:-unknown}"
    BACKUP_TYPE="''${2:-general}"
    DETAILS="''${3:-No details}"

    log "Backup notification: $BACKUP_TYPE - $STATUS"

    if [ "$STATUS" = "success" ]; then
      SEVERITY="info"
      TITLE="Backup Succeeded: $BACKUP_TYPE"
      MESSAGE="$BACKUP_TYPE backup completed successfully"
      log "  Result: SUCCESS"
    else
      SEVERITY="critical"
      TITLE="Backup Failed: $BACKUP_TYPE"
      MESSAGE="$BACKUP_TYPE backup failed: $DETAILS"
      log "  Result: FAILED - $DETAILS"
    fi

    EXTRA=$(${pkgs.jq}/bin/jq -n \
      --arg backup_type "$BACKUP_TYPE" \
      --arg status "$STATUS" \
      --arg details "$DETAILS" \
      '{
        backup_type: $backup_type,
        status: $status,
        details: $details,
        source: "backup"
      }')

    ${webhookSender}/bin/hwc-webhook-send \
      backup \
      "$TITLE" \
      "$MESSAGE" \
      "$SEVERITY" \
      "$EXTRA" || {
        log "  WARNING: Failed to send webhook, alert logged locally"
        if [ "$STATUS" != "success" ]; then
          echo "BACKUP FAILED: $BACKUP_TYPE - $DETAILS" | ${pkgs.util-linux}/bin/wall 2>/dev/null || true
        fi
      }
  '';

in
{
  inherit webhookSender webhookHealthCheck smartdNotify serviceFailureNotify diskSpaceCheck backupNotify;
}
