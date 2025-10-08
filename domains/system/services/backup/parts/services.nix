# NEW file: domains/system/services/backup/parts/3-services.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

  backupMaintenanceScript = pkgs.writeScriptBin "backup-maintenance" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Backup System Maintenance ==="

    if [[ -f "/etc/rclone-proton.conf" ]] || [[ -f "/root/.config/rclone/rclone.conf" ]]; then
      echo "✅ Rclone configuration found"

      echo "Testing Proton Drive connection..."
      if ${pkgs.rclone}/bin/rclone lsd proton: >/dev/null 2>&1; then
        echo "✅ Proton Drive connection working"
      else
        echo "❌ Proton Drive connection failed"
      fi
    else
      echo "❌ No rclone configuration found"
    fi

    if mountpoint -q "/mnt/backup" 2>/dev/null; then
      echo "✅ External backup drive mounted"
      df -h "/mnt/backup"
    else
      echo "ℹ️  No external backup drive mounted"
    fi
  '';
in
{
  config = lib.mkIf cfg.enable {
    # --- Rclone Configuration ---
    environment.etc."rclone-proton.conf" = lib.mkIf cfg.protonDrive.enable {
      source = config.age.secrets.${cfg.protonDrive.secretName}.path;
      mode = "0600"; # Secure permissions
    };

    # --- Systemd Services & Timers ---
    systemd.services.backup-system-info = lib.mkIf cfg.monitoring.enable {
      description = "Backup system information and health check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupMaintenanceScript}/bin/backup-maintenance";
        User = "root";
      };
    };
    systemd.timers.backup-system-info = lib.mkIf cfg.monitoring.enable {
      description = "Weekly backup system maintenance check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    # --- Log Rotation ---
    services.logrotate.settings.rclone = lib.mkIf cfg.protonDrive.enable {
      files = [ "/var/log/rclone.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
    };

    # --- Validation ---
    assertions = [
      {
        assertion = !cfg.protonDrive.enable || (config.age.secrets ? "${cfg.protonDrive.secretName}");
        message = "Proton Drive is enabled, but the secret '${cfg.protonDrive.secretName}' was not found.";
      }
    ];
  };
}
