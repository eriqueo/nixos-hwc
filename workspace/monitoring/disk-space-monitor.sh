#!/usr/bin/env bash
# Disk space monitoring with tiered gotify alerts
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
    # Critical alert - priority 10
    hwc-gotify-send --priority 10 \
      "CRITICAL: Disk Space" \
      "[$HOSTNAME] $fs_name at ${USAGE}%!
Available: $AVAILABLE
Immediate cleanup required."
  elif [ "$USAGE" -gt "$WARNING_THRESHOLD" ]; then
    # Warning alert - priority 7
    hwc-gotify-send --priority 7 \
      "Disk Space Warning" \
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
