# Storage monitoring automation
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.storage.monitoring;
  storageCfg = config.hwc.services.storage;

  monitorScript = pkgs.writeShellScript "storage-monitor" ''
    set -euo pipefail

    THRESHOLD=${toString cfg.alertThreshold}

    echo "$(date): Starting storage monitoring (threshold: $THRESHOLD%)"

    # Check main storage paths
    for path in "${config.hwc.paths.hot}" "${config.hwc.paths.media}"; do
      if [ -d "$path" ]; then
        usage=$(df "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
        echo "Storage usage for $path: $usage%"

        if [ "$usage" -gt "$THRESHOLD" ]; then
          echo "WARNING: Storage usage for $path exceeds threshold ($usage% > $THRESHOLD%)"
          # Log to system journal for alerting
          logger -t storage-monitor "WARNING: Storage usage for $path exceeds threshold ($usage% > $THRESHOLD%)"
        fi
      fi
    done

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
      path = [ pkgs.coreutils pkgs.util-linux ];
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