# Storage monitoring automation
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.storage.monitoring;
  storageCfg = config.hwc.services.storage;

  monitorScript = pkgs.writeShellScript "storage-monitor" ''
    set -euo pipefail

    THRESHOLD=${toString cfg.alertThreshold}

    echo "$(date): Starting storage monitoring (threshold: $THRESHOLD%)"

    # Check critical system paths (with lower threshold for root)
    declare -A paths_to_check=(
      ["/"]="75"                              # Root partition - critical, lower threshold
      ["/var/log"]="80"                       # Log directory - where our issue occurred
      ["${config.hwc.paths.hot}"]="$THRESHOLD"     # Hot storage
      ["${config.hwc.paths.media}"]="$THRESHOLD"   # Media storage
    )

    for path in "''${!paths_to_check[@]}"; do
      if [ -d "$path" ]; then
        path_threshold="''${paths_to_check[$path]}"
        usage=$(df "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
        echo "Storage usage for $path: $usage% (threshold: $path_threshold%)"

        if [ "$usage" -gt "$path_threshold" ]; then
          echo "WARNING: Storage usage for $path exceeds threshold ($usage% > $path_threshold%)"
          # Log to system journal for alerting
          logger -p user.warning -t storage-monitor "CRITICAL: Storage usage for $path exceeds threshold ($usage% > $path_threshold%)"

          # If root partition is >90%, this is critical
          if [[ "$path" == "/" ]] && [ "$usage" -gt "90" ]; then
            logger -p user.crit -t storage-monitor "CRITICAL: Root partition at $usage% - immediate attention required"
          fi
        fi
      fi
    done

    # Check specific log directories for large files
    if [ -d "/var/log/caddy" ]; then
      large_logs=$(find /var/log/caddy -name "*.log" -size +50M -exec ls -lh {} \; 2>/dev/null)
      if [ -n "$large_logs" ]; then
        echo "WARNING: Large Caddy log files detected:"
        echo "$large_logs"
        logger -p user.warning -t storage-monitor "Large Caddy log files detected - may need rotation"
      fi
    fi

    echo "$(date): Storage monitoring completed"
  '';
in
{
  config = lib.mkIf (storageCfg.enable && cfg.enable) {
    # Storage monitoring service
    systemd.services.storage-monitor = {
      description = "Storage usage monitoring";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${monitorScript}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      path = [ pkgs.coreutils pkgs.util-linux pkgs.gawk ];
    };

    # Storage monitoring timer (runs every hour)
    systemd.timers.storage-monitor = {
      description = "Storage monitoring timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5m";
        Persistent = true;
        AccuracySec = "10m";
      };
    };
  };
}