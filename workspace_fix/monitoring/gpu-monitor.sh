#!/usr/bin/env bash
# GPU temperature monitoring with tiered alerts
# Usage: Run via systemd timer (every 5 minutes recommended)

set -euo pipefail

HOSTNAME=$(hostname)
CRITICAL_TEMP=85
WARNING_TEMP=75

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
  exit 0
fi

# Get GPU temperature
GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
GPU_MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)

if [ -z "$GPU_TEMP" ]; then
  exit 0
fi

if [ "$GPU_TEMP" -gt "$CRITICAL_TEMP" ]; then
  # Critical temperature - P5
  hwc-ntfy-send --priority 5 --tag gpu,temperature,critical \
    hwc-critical \
    "🔥 CRITICAL: GPU Temperature" \
    "[$HOSTNAME] $GPU_NAME at ${GPU_TEMP}°C!
Utilization: ${GPU_UTIL}%
Memory: $GPU_MEM
Thermal throttling likely. Check cooling."

elif [ "$GPU_TEMP" -gt "$WARNING_TEMP" ]; then
  # Warning temperature - P4
  hwc-ntfy-send --priority 4 --tag gpu,temperature,warning \
    hwc-alerts \
    "🌡️ GPU Temperature Warning" \
    "[$HOSTNAME] $GPU_NAME at ${GPU_TEMP}°C
Utilization: ${GPU_UTIL}%
Memory: $GPU_MEM
Monitor closely."
fi

# Check for sustained high utilization (>80% for extended period)
# This could be tracked with state file, but for now just notify if critical
if [ "$GPU_UTIL" -gt 95 ]; then
  hwc-ntfy-send --priority 2 --tag gpu,utilization \
    hwc-monitoring \
    "💻 GPU High Utilization" \
    "[$HOSTNAME] $GPU_NAME at ${GPU_UTIL}%
Temperature: ${GPU_TEMP}°C
Memory: $GPU_MEM"
fi

exit 0
