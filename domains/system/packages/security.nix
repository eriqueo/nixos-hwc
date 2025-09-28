# HWC Charter Module/domains/system/backup-packages.nix
#
# BACKUP PACKAGES - System packages and tools for backup operations
# Provides rclone, backup utilities, and Proton Drive configuration management
#
# DEPENDENCIES (Upstream):
#   - config.age.secrets.* (agenix secrets for cloud credentials)
#   - config.hwc.system.users.* (user configuration)
#
# USED BY (Downstream):
#   - modules/services/backup/user-backup.nix (backup service)
#   - profiles/*.nix (enables via hwc.system.backupPackages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix or profiles/server.nix: ../domains/system/backup-packages.nix
#
# USAGE:
#   hwc.system.backupPackages.enable = true;
#   hwc.system.backupPackages.protonDrive.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.backupPackages;
  userCfg = config.hwc.system.users;
  
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
  
in {
  #============================================================================
  # OPTIONS - Backup packages configuration
  #============================================================================
  
  options.hwc.system.backupPackages = {
    enable = lib.mkEnableOption "backup system packages and utilities";
    
    # Cloud storage configuration
    protonDrive = {
      enable = lib.mkEnableOption "Proton Drive integration";
      
      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Proton Mail email address (leave empty to use interactive setup)";
      };
      
      encodedPassword = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Rclone-encoded password (leave empty to use interactive setup)";
      };
      
      useSecret = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use agenix secret for rclone configuration";
      };
      
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "rclone-proton-config";
        description = "Name of agenix secret containing rclone config";
      };
    };
    
    # Additional backup tools
    extraTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional backup-related packages to install";
    };
    
    # Maintenance and monitoring
    monitoring = {
      enable = lib.mkEnableOption "backup monitoring and maintenance tools";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Backup system packages
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    
    # Validation assertions
    assertions = [
      {
        assertion = !cfg.protonDrive.useSecret || (config.age.secrets ? "${cfg.protonDrive.secretName}");
        message = "Proton Drive secret '${cfg.protonDrive.secretName}' not found but useSecret is enabled";
      }
    ];
    
    # Core backup packages
    environment.systemPackages = with pkgs; [
      # Cloud storage tools
      rclone              # Multi-cloud sync tool
      rsync               # Local sync and backup
      
      # Archive and compression
      gnutar              # Archive creation
      gzip                # Compression
      p7zip               # 7z archives
      
      # Filesystem tools
      util-linux          # mount, umount, blkid
      findutils           # find for file discovery
      coreutils           # basic utilities (du, chmod, etc.)
      
      # Network tools for cloud backup
      curl                # HTTP transfers
      wget                # File downloads
      
      # Monitoring and logging
      logrotate           # Log rotation
      
    ] ++ lib.optionals cfg.protonDrive.enable [
      # Proton Drive specific tools
      configureRcloneScript
      
    ] ++ lib.optionals cfg.monitoring.enable [
      # Monitoring and maintenance
      backupMaintenanceScript
      
    ] ++ cfg.extraTools;
    
    # Proton Drive rclone configuration
    environment.etc."rclone-proton.conf" = lib.mkIf (cfg.protonDrive.enable && cfg.protonDrive.useSecret) {
      source = config.age.secrets.${cfg.protonDrive.secretName}.path;
      mode = "0600";
    };
    
    # Alternative: Direct configuration (less secure, for development)
    environment.etc."rclone-proton-template.conf" = lib.mkIf (cfg.protonDrive.enable && !cfg.protonDrive.useSecret && cfg.protonDrive.email != "") {
      text = protonRcloneConfig;
      mode = "0600";
    };
    
    # Create rclone config directory
    systemd.tmpfiles.rules = lib.optionals cfg.protonDrive.enable [
      "d /root/.config/rclone 0700 root root -"
    ];
    
    # Backup system information service
    systemd.services.backup-system-info = lib.mkIf cfg.monitoring.enable {
      description = "Backup system information and health check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupMaintenanceScript}/bin/backup-maintenance";
        User = "root";
        
        # Security
        PrivateTmp = true;
        NoNewPrivileges = true;
        
        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
    
    # Weekly maintenance timer
    systemd.timers.backup-system-info = lib.mkIf cfg.monitoring.enable {
      description = "Weekly backup system maintenance check";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    # Log rotation for rclone logs
    services.logrotate.settings.rclone = lib.mkIf cfg.protonDrive.enable {
      files = [ "/var/log/rclone.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
    
    # Helpful environment variables
    environment.sessionVariables = lib.mkIf cfg.protonDrive.enable {
      RCLONE_CONFIG = "/etc/rclone-proton.conf";
    };
    
    # Warnings for incomplete configuration
    warnings = lib.optionals (cfg.protonDrive.enable && !cfg.protonDrive.useSecret && cfg.protonDrive.email == "") [
      ''
        Proton Drive is enabled but no credentials configured.
        Run 'configure-proton-rclone' to set up authentication.
      ''
    ];
  };
}