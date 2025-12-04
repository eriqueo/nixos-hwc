#!/usr/bin/env bash
# Generic systemd service failure notifier
# Usage: systemd.services.<name>.onFailure = [ "ntfy-service-failure@%n.service" ]

set -euo pipefail

SERVICE_NAME="${1:-%i}"
HOSTNAME=$(hostname)

# Get service status details
STATUS=$(systemctl status "$SERVICE_NAME" --no-pager --lines=10 2>&1 || true)
FAILED_SINCE=$(systemctl show "$SERVICE_NAME" -p ActiveEnterTimestamp --value)

# Determine priority based on service importance
PRIORITY=5  # Default to critical
TOPIC="hwc-critical"

# Lower priority for less critical services
case "$SERVICE_NAME" in
  *backup*|*sync*)
    PRIORITY=5
    TOPIC="hwc-critical"
    ;;
  *jellyfin*|*immich*|*navidrome*)
    PRIORITY=5
    TOPIC="hwc-critical"
    ;;
  *frigate*|*couchdb*|*ollama*)
    PRIORITY=4
    TOPIC="hwc-alerts"
    ;;
  *)
    PRIORITY=4
    TOPIC="hwc-alerts"
    ;;
esac

# Send notification
hwc-ntfy-send --priority "$PRIORITY" --tag service,failure \
  "$TOPIC" \
  "❌ Service Failed: $SERVICE_NAME" \
  "[$HOSTNAME] Service $SERVICE_NAME has failed.

Failed since: $FAILED_SINCE

Recent logs:
$(journalctl -u "$SERVICE_NAME" -n 5 --no-pager)

Check: journalctl -u $SERVICE_NAME"

exit 0
