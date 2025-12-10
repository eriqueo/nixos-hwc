#!/usr/bin/env bash
# Daily system summary notification
# Usage: Run via systemd timer (daily at 8 AM recommended)

set -euo pipefail

HOSTNAME=$(hostname)

# System uptime
UPTIME=$(uptime -p)

# Disk usage summary
DISK_SUMMARY=$(df -h / /home 2>/dev/null | awk 'NR>1 {printf "%s: %s/%s (%s)\n", $6, $3, $2, $5}')

# Memory usage
MEM_TOTAL=$(free -h | awk 'NR==2{print $2}')
MEM_USED=$(free -h | awk 'NR==2{print $3}')
MEM_PERCENT=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')

# Load average
LOAD=$(uptime | awk -F'load average:' '{print $2}')

# GPU stats (if available)
GPU_STATS=""
if command -v nvidia-smi &> /dev/null; then
  GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "N/A")
  GPU_STATS="

GPU: $GPU_NAME
Temp: ${GPU_TEMP}°C"
fi

# Service status (key services)
SERVICES_DOWN=0
SERVICE_STATUS=""

check_service() {
  local service="$1"
  if systemctl is-active --quiet "$service" 2>/dev/null; then
    SERVICE_STATUS+="✅ $service
"
  else
    SERVICE_STATUS+="❌ $service (DOWN)
"
    SERVICES_DOWN=$((SERVICES_DOWN + 1))
  fi
}

# Check key services based on machine
if [ "$HOSTNAME" = "hwc-server" ]; then
  check_service "caddy"
  check_service "jellyfin"
  check_service "immich-server"
  check_service "navidrome"
  check_service "frigate"
elif [ "$HOSTNAME" = "hwc-laptop" ]; then
  check_service "NetworkManager"
  check_service "tailscaled"
fi

# Recent failed services (last 24h)
FAILED_SERVICES=$(systemctl list-units --state=failed --plain --no-legend | awk '{print $1}' | head -5)
FAILED_COUNT=$(echo "$FAILED_SERVICES" | grep -c . || echo 0)

# Build message
MESSAGE="📊 Daily System Summary

Uptime: $UPTIME
Load: $LOAD

💾 Disk Usage:
$DISK_SUMMARY

🧠 Memory: $MEM_USED/$MEM_TOTAL ($MEM_PERCENT%)$GPU_STATS

🔧 Service Status:
$SERVICE_STATUS"

if [ "$FAILED_COUNT" -gt 0 ]; then
  MESSAGE+="
⚠️ Failed Services (24h):
$FAILED_SERVICES"
fi

# Determine priority and topic
if [ "$SERVICES_DOWN" -gt 0 ] || [ "$FAILED_COUNT" -gt 0 ]; then
  PRIORITY=4
  TOPIC="hwc-alerts"
else
  PRIORITY=2
  TOPIC="hwc-monitoring"
fi

# Send notification
hwc-ntfy-send --priority "$PRIORITY" --tag monitoring,daily \
  "$TOPIC" \
  "📊 [$HOSTNAME] Daily Summary" \
  "$MESSAGE"

exit 0
