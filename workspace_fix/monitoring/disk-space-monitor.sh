#!/usr/bin/env bash
# Disk space monitoring with tiered ntfy alerts
# Usage: Run via systemd timer (hourly recommended)

set -euo pipefail

HOSTNAME=$(hostname)
CRITICAL_THRESHOLD=95
WARNING_THRESHOLD=80

# Check root filesystem
check_filesystem() {
  local mount_point="$1"
  local fs_name="${2:-$mount_point}"

  if ! mountpoint -q "$mount_point"; then
    return 0
  fi

  USAGE=$(df "$mount_point" | awk 'NR==2 {print $5}' | sed 's/%//')
  AVAILABLE=$(df -h "$mount_point" | awk 'NR==2 {print $4}')

  if [ "$USAGE" -gt "$CRITICAL_THRESHOLD" ]; then
    # Critical alert - P5
    hwc-ntfy-send --priority 5 --tag disk,critical \
      hwc-critical \
      "🚨 CRITICAL: Disk Space" \
      "[$HOSTNAME] $fs_name at ${USAGE}%!
Available: $AVAILABLE
Immediate cleanup required."
  elif [ "$USAGE" -gt "$WARNING_THRESHOLD" ]; then
    # Warning alert - P4
    hwc-ntfy-send --priority 4 --tag disk,warning \
      hwc-alerts \
      "⚠️ Disk Space Warning" \
      "[$HOSTNAME] $fs_name at ${USAGE}%
Available: $AVAILABLE
Consider cleanup soon."
  fi
}

# Check all major filesystems
check_filesystem "/" "Root"
check_filesystem "/home" "Home"
check_filesystem "/mnt/media" "Media Storage" || true
check_filesystem "/mnt/hot" "Hot Storage" || true
check_filesystem "/mnt/backup" "Backup Drive" || true

exit 0
