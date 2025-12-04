#!/usr/bin/env bash
# NixOS rebuild notification wrapper
# Usage: Wrap nixos-rebuild commands to send notifications
# Example: nixos-rebuild-notifier switch

set -euo pipefail

HOSTNAME=$(hostname)
OPERATION="${1:-switch}"
shift || true

# Get current generation before rebuild
BEFORE_GEN=$(nixos-rebuild list-generations | grep current | awk '{print $1}')

# Run the rebuild
START_TIME=$(date +%s)
if nixos-rebuild "$OPERATION" --flake .#"$HOSTNAME" "$@" 2>&1 | tee /tmp/nixos-rebuild.log; then
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  AFTER_GEN=$(nixos-rebuild list-generations | grep current | awk '{print $1}')

  # Success notification - P1 (low priority)
  hwc-ntfy-send --priority 1 --tag nixos,rebuild,success \
    hwc-updates \
    "✅ NixOS Rebuild Success" \
    "[$HOSTNAME] System rebuilt successfully

Operation: $OPERATION
Generation: $BEFORE_GEN → $AFTER_GEN
Duration: ${DURATION}s

Log: /tmp/nixos-rebuild.log"

  exit 0
else
  # Failure notification - P4 (important)
  ERROR_LOG=$(tail -20 /tmp/nixos-rebuild.log)

  hwc-ntfy-send --priority 4 --tag nixos,rebuild,failure \
    hwc-alerts \
    "❌ NixOS Rebuild Failed" \
    "[$HOSTNAME] Rebuild failed!

Operation: $OPERATION
Generation: $BEFORE_GEN (unchanged)

Last 20 lines:
$ERROR_LOG

Full log: /tmp/nixos-rebuild.log"

  exit 1
fi
