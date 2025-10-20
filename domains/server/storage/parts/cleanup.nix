# Storage cleanup automation
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.storage.cleanup;
  storageCfg = config.hwc.services.storage;

  cleanupScript = pkgs.writeShellScript "media-cleanup" ''
    set -euo pipefail

    # Log cleanup start
    echo "$(date): Starting media cleanup (retention: ${toString cfg.retentionDays} days)"

    # Clean up temporary files older than retention period
    ${lib.concatMapStringsSep "\n" (path: ''
      if [ -d "${path}" ]; then
        echo "Cleaning ${path}..."
        find "${path}" -type f -mtime +${toString cfg.retentionDays} -delete || true
        find "${path}" -type d -empty -delete || true
        echo "Cleaned ${path}"
      else
        echo "Directory ${path} does not exist, skipping"
      fi
    '') cfg.paths}

    # Clean up Docker/Podman logs if they exist
    if [ -d "/var/lib/containers" ]; then
      echo "Cleaning container logs..."
      find /var/lib/containers -name "*.log" -mtime +${toString cfg.retentionDays} -delete || true
    fi

    # Clean up systemd journal logs older than retention
    if command -v journalctl >/dev/null 2>&1; then
      echo "Cleaning systemd journal..."
      journalctl --vacuum-time=${toString cfg.retentionDays}d || true
    fi

    echo "$(date): Media cleanup completed"
  '';
in
{
  config = lib.mkIf (storageCfg.enable && cfg.enable) {
    # Cleanup service
    systemd.services.media-cleanup = {
      description = "Media server temporary file cleanup";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${cleanupScript}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      path = [ pkgs.findutils pkgs.coreutils ];
    };

    # Cleanup timer
    systemd.timers.media-cleanup = {
      description = "Media cleanup timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.schedule;
        RandomizedDelaySec = "1h";
        Persistent = true;
        AccuracySec = "1h";
      };
    };

    # Log rotation for cleanup logs
    services.logrotate.settings.media-cleanup = {
      files = [ "/var/log/media-cleanup.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
  };
}