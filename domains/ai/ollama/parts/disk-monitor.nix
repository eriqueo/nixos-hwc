{ pkgs, config }:

let
  cfg = config.hwc.ai.ollama;
in
pkgs.writeShellScript "ollama-disk-monitor" ''
  set -euo pipefail

  DATA_DIR="${cfg.dataDir}"
  WARN_THRESHOLD=${toString cfg.diskMonitoring.warningThreshold}
  CRIT_THRESHOLD=${toString cfg.diskMonitoring.criticalThreshold}

  # Get disk usage percentage for the data directory
  USAGE=$(${pkgs.coreutils}/bin/df "$DATA_DIR" | ${pkgs.gawk}/bin/awk 'NR==2 {print $5}' | ${pkgs.gnused}/bin/sed 's/%//')

  echo "Ollama model storage: $DATA_DIR"
  echo "Current disk usage: $USAGE%"

  # Calculate actual disk space used
  TOTAL=$(${pkgs.coreutils}/bin/df -h "$DATA_DIR" | ${pkgs.gawk}/bin/awk 'NR==2 {print $2}')
  USED=$(${pkgs.coreutils}/bin/df -h "$DATA_DIR" | ${pkgs.gawk}/bin/awk 'NR==2 {print $3}')
  AVAIL=$(${pkgs.coreutils}/bin/df -h "$DATA_DIR" | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}')

  echo "Total: $TOTAL | Used: $USED | Available: $AVAIL"

  # Check thresholds
  if [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
    echo "❌ CRITICAL: Disk usage at $USAGE% (threshold: $CRIT_THRESHOLD%)"
    echo "Action required: Clean up old models or expand storage"
    exit 1
  elif [ "$USAGE" -ge "$WARN_THRESHOLD" ]; then
    echo "⚠️  WARNING: Disk usage at $USAGE% (threshold: $WARN_THRESHOLD%)"
    echo "Consider cleaning up unused models"
    exit 0
  else
    echo "✓ Disk usage healthy ($USAGE% < $WARN_THRESHOLD%)"
    exit 0
  fi
''
