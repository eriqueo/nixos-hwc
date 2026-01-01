# Storage cleanup automation
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.native.storage.cleanup;
  storageCfg = config.hwc.server.native.storage;

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

    # Clean up Caddy logs (critical - these caused our disk space issue)
    if [ -d "/var/log/caddy" ]; then
      echo "Cleaning Caddy logs..."
      # Remove old rotated logs
      find /var/log/caddy -name "*.log.gz" -mtime +${toString cfg.retentionDays} -delete || true

      # Truncate active logs larger than 50MB to prevent disk space issues
      find /var/log/caddy -name "*.log" -size +50M -exec truncate -s 50M {} \; || true
      echo "Truncated large Caddy logs (>50MB) to prevent disk space issues"
    fi

    # Clean up systemd journal logs older than retention
    if command -v journalctl >/dev/null 2>&1; then
      echo "Cleaning systemd journal..."
      journalctl --vacuum-time=${toString cfg.retentionDays}d || true
    fi

    # Clean up other system logs that can grow large
    if [ -d "/var/log" ]; then
      echo "Cleaning other system logs..."
      # Remove old wtmp/btmp logs
      find /var/log -name "wtmp.*" -o -name "btmp.*" -mtime +${toString cfg.retentionDays} -delete || true

      # Truncate large syslog files if they exist
      find /var/log -name "syslog" -o -name "messages" -size +100M -exec truncate -s 50M {} \; || true
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

    # Critical: Log rotation for Caddy logs to prevent disk space issues
    services.logrotate.settings.caddy = {
      files = [ "/var/log/caddy/*.log" ];
      frequency = "daily";
      rotate = 7;
      size = "50M";  # Rotate when files reach 50MB
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 caddy caddy";
      postrotate = ''
        systemctl reload caddy.service || true
      '';
    };
  };
}