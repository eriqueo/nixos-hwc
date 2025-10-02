# NEW file: domains/system/services/backup/parts/2-scripts.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;

 # Backup maintenance script
  backupMaintenanceScript = pkgs.writeScriptBin "backup-maintenance" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "=== Backup System Maintenance ==="
    
    # Check rclone configuration
    if [[ -f "/etc/rclone-proton.conf" ]] || [[ -f "/root/.config/rclone/rclone.conf" ]]; then
      echo "✅ Rclone configuration found"
      
      # Test Proton Drive connection
      echo "Testing Proton Drive connection..."
      if ${pkgs.rclone}/bin/rclone lsd proton: >/dev/null 2>&1; then
        echo "✅ Proton Drive connection working"
      else
        echo "❌ Proton Drive connection failed"
      fi
    else
      echo "❌ No rclone configuration found"
      echo "Run 'configure-proton-rclone' to set up Proton Drive"
    fi
    
    # Check external drive mount point
    if mountpoint -q "/mnt/backup" 2>/dev/null; then
      echo "✅ External backup drive mounted"
      
      # Show disk usage
      echo "External drive usage:"
      df -h "/mnt/backup"
    else
      echo "ℹ️  No external backup drive mounted"
    fi
    
    # Check backup logs
    if [[ -f "/var/log/user-backup.log" ]]; then
      echo
      echo "Recent backup activity:"
      tail -n 5 /var/log/user-backup.log
    fi
    
    # Check systemd services
    echo
    echo "Backup service status:"
    systemctl status user-backup.service --no-pager -l || true
    
    if systemctl is-enabled user-backup.timer >/dev/null 2>&1; then
      echo
      echo "Backup timer status:"
      systemctl status user-backup.timer --no-pager -l || true
      
      echo
      echo "Next scheduled backup:"
      systemctl list-timers user-backup.timer --no-pager || true
    fi
  '';
   # Rclone configuration template for Proton Drive
  protonRcloneConfig = ''
    [proton]
    type = webdav
    url = https://drive.proton.me/urls/remote.php/webdav/
    vendor = owncloud
    user = ${cfg.protonDrive.email}
    pass = ${cfg.protonDrive.encodedPassword}
    headers = User-Agent,proton-drive/1.0.0
  '';
  
  # Helper script to configure rclone for Proton Drive
  configureRcloneScript = pkgs.writeScriptBin "configure-proton-rclone" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "=== Proton Drive rclone Configuration ==="
    echo
    echo "This script will help you set up rclone for Proton Drive backup."
    echo "You'll need your Proton Mail credentials."
    echo
    
    # Get user input
    read -p "Enter your Proton Mail email: " EMAIL
    read -s -p "Enter your Proton Mail password: " PASSWORD
    echo
    
    # Encode password for rclone
    ENCODED_PASSWORD=$(echo -n "$PASSWORD" | ${pkgs.rclone}/bin/rclone obscure -)
    
    # Create rclone config directory
    CONFIG_DIR="/root/.config/rclone"
    mkdir -p "$CONFIG_DIR"
    
    # Generate config file
    cat > "$CONFIG_DIR/rclone.conf" << EOF
    [proton]
    type = webdav
    url = https://drive.proton.me/urls/remote.php/webdav/
    vendor = owncloud
    user = $EMAIL
    pass = $ENCODED_PASSWORD
    headers = User-Agent,proton-drive/1.0.0
    EOF
    
    chmod 600 "$CONFIG_DIR/rclone.conf"
    
    echo
    echo "✅ Proton Drive configuration saved to: $CONFIG_DIR/rclone.conf"
    echo
    echo "Testing connection..."
    if ${pkgs.rclone}/bin/rclone lsd proton: >/dev/null 2>&1; then
      echo "✅ Connection successful!"
      echo
      echo "You can now use rclone with Proton Drive:"
      echo "  rclone ls proton:"
      echo "  rclone sync /path/to/local proton:Backups/"
    else
      echo "❌ Connection failed. Please check your credentials."
      exit 1
    fi
  '';
in
{
  config = lib.mkIf cfg.monitoring.enable {
    # We only add the script to the system path if monitoring is enabled.
    environment.systemPackages = [ backupMaintenanceScript ];
  };
}
