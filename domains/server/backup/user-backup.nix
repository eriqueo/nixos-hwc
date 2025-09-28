# HWC Charter Module/domains/services/backup/user-backup.nix
#
# USER BACKUP - Intelligent user data backup with external drive detection and cloud fallback
# Provides automated backup with external drive priority and Proton Drive fallback
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.system.users.* (modules/system/users.nix)
#   - config.age.secrets.* (agenix secrets for Proton Drive)
#   - rclone package (modules/system/backup-packages.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.services.backup.user.enable)
#   - machines/*.nix (configures external drive settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix or profiles/server.nix: ../domains/services/backup/user-backup.nix
#
# USAGE:
#   hwc.services.backup.user.enable = true;
#   hwc.services.backup.user.externalDrive.enable = true;
#   hwc.services.backup.user.protonDrive.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.backup.user;
  paths = config.hwc.paths;
  userCfg = config.hwc.system.users;
  
  # Backup script with intelligent drive detection and fallback
  backupScript = pkgs.writeShellScript "user-backup" ''
    set -euo pipefail
    
    # Logging functions
    log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"; }
    log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1"; }
    log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2; }
    
    # Configuration
    USER_HOME="${paths.user.home}"
    EXTERNAL_MOUNT="${cfg.externalDrive.mountPoint}"
    BACKUP_NAME="$(${pkgs.nettools}/bin/hostname)_${userCfg.user.name}_$(date +%Y%m%d_%H%M%S)"
    LOG_FILE="/var/log/user-backup.log"
    
    # Check if external drive is mounted and has space
    check_external_drive() {
      if [[ ! -d "$EXTERNAL_MOUNT" ]]; then
        log_warn "External drive mount point $EXTERNAL_MOUNT does not exist"
        return 1
      fi
      
      if ! mountpoint -q "$EXTERNAL_MOUNT"; then
        log_warn "External drive not mounted at $EXTERNAL_MOUNT"
        return 1
      fi
      
      # Check available space (require at least ${toString cfg.externalDrive.minSpaceGB}GB)
      AVAILABLE_GB=$(df -BG "$EXTERNAL_MOUNT" | awk 'NR==2 {print $4}' | sed 's/G//')
      if [[ "$AVAILABLE_GB" -lt ${toString cfg.externalDrive.minSpaceGB} ]]; then
        log_warn "External drive has only $${AVAILABLE_GB}GB free, need at least ${toString cfg.externalDrive.minSpaceGB}GB"
        return 1
      fi
      
      log_info "External drive available with $${AVAILABLE_GB}GB free space"
      return 0
    }
    
    # Backup to external drive
    backup_to_external() {
      local backup_dir="$EXTERNAL_MOUNT/backups/$(hostname)"
      local backup_path="$backup_dir/$BACKUP_NAME.tar.gz"
      
      log_info "Starting backup to external drive: $backup_path"
      
      # Create backup directory
      mkdir -p "$backup_dir"
      
      # Create tar archive with exclusions
      tar -czf "$backup_path" \
        --exclude='$USER_HOME/.cache' \
        --exclude='$USER_HOME/.local/share/Trash' \
        --exclude='$USER_HOME/.mozilla/firefox/*/storage/default' \
        --exclude='$USER_HOME/.thunderbird/*/ImapMail' \
        --exclude='$USER_HOME/Downloads/*.iso' \
        --exclude='$USER_HOME/Downloads/*.img' \
        --exclude='**/node_modules' \
        --exclude='**/__pycache__' \
        --exclude='$USER_HOME/99-temp' \
        -C "$(dirname "$USER_HOME")" \
        "$(basename "$USER_HOME")"
      
      # Verify backup was created
      if [[ -f "$backup_path" ]]; then
        local size_mb=$(du -m "$backup_path" | cut -f1)
        log_info "External backup completed: $backup_path ($${size_mb}MB)"
        
        # Clean old backups (keep last ${toString cfg.externalDrive.keepDays} days)
        find "$backup_dir" -name "*.tar.gz" -mtime +${toString cfg.externalDrive.keepDays} -delete
        log_info "Cleaned backups older than ${toString cfg.externalDrive.keepDays} days"
        
        return 0
      else
        log_error "External backup failed: file not created"
        return 1
      fi
    }
    
    # Backup to Proton Drive via rclone
    backup_to_proton() {
      log_info "Starting backup to Proton Drive"
      
      # Sync user home to Proton Drive with exclusions
      ${pkgs.rclone}/bin/rclone sync "$USER_HOME" "proton:Backups/$(hostname)/${userCfg.user.name}" \
        --config "${cfg.protonDrive.configPath}" \
        --exclude ".cache/**" \
        --exclude ".local/share/Trash/**" \
        --exclude ".mozilla/firefox/*/storage/default/**" \
        --exclude ".thunderbird/*/ImapMail/**" \
        --exclude "Downloads/*.iso" \
        --exclude "Downloads/*.img" \
        --exclude "**/node_modules/**" \
        --exclude "**/__pycache__/**" \
        --exclude "99-temp/**" \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --delete-during
      
      if [[ $? -eq 0 ]]; then
        log_info "Proton Drive backup completed successfully"
        return 0
      else
        log_error "Proton Drive backup failed"
        return 1
      fi
    }
    
    # Main backup logic
    main() {
      log_info "=== User Backup Started for ${userCfg.user.name} ==="
      
      # Redirect output to log file while keeping stdout
      exec > >(tee -a "$LOG_FILE")
      exec 2> >(tee -a "$LOG_FILE" >&2)
      
      local backup_success=false
      
      # Try external drive first if enabled
      if [[ "${toString cfg.externalDrive.enable}" == "true" ]]; then
        if check_external_drive; then
          if backup_to_external; then
            backup_success=true
          fi
        fi
      fi
      
      # Try Proton Drive if external failed or not available
      if [[ "$backup_success" != true ]] && [[ "${toString cfg.protonDrive.enable}" == "true" ]]; then
        if backup_to_proton; then
          backup_success=true
        fi
      fi
      
      # Report results
      if [[ "$backup_success" == true ]]; then
        log_info "=== Backup completed successfully ==="
        ${lib.optionalString cfg.notifications.enable ''
          # Log success (desktop notifications don't work in system context)
          logger "Backup Complete: User data backed up successfully"
        ''}
        exit 0
      else
        log_error "=== All backup methods failed ==="
        ${lib.optionalString cfg.notifications.enable ''
          # Log failure (desktop notifications don't work in system context)  
          logger -p user.err "Backup Failed: All backup methods failed"
        ''}
        exit 1
      fi
    }
    
    main "$@"
  '';
  
in {
  #============================================================================
  # OPTIONS - User backup configuration
  #============================================================================
  
  options.hwc.services.backup.user = {
    enable = lib.mkEnableOption "intelligent user data backup service";
    
    username = lib.mkOption {
      type = lib.types.str;
      default = userCfg.user.name or "eric";
      description = "Username to backup";
    };
    
    # External drive configuration
    externalDrive = {
      enable = lib.mkEnableOption "external drive backup (primary method)";
      
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/backup";
        description = "External drive mount point";
      };
      
      minSpaceGB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Minimum free space required (GB) before attempting backup";
      };
      
      keepDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Days to keep old backups on external drive";
      };
    };
    
    # Proton Drive configuration  
    protonDrive = {
      enable = lib.mkEnableOption "Proton Drive backup (fallback method)";
      
      configPath = lib.mkOption {
        type = lib.types.str;
        default = "/etc/rclone-proton.conf";
        description = "Path to rclone config file for Proton Drive";
      };
      
      useSecret = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use agenix secret for rclone config";
      };
      
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "rclone-proton-config";
        description = "Agenix secret name for rclone config";
      };
    };
    
    # Scheduling options
    schedule = {
      enable = lib.mkEnableOption "automatic backup scheduling";
      
      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Backup frequency (systemd calendar format)";
      };
      
      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Random delay to spread backup load";
      };
    };
    
    # Notification options
    notifications = {
      enable = lib.mkEnableOption "desktop notifications for backup status";
    };
  };

  #============================================================================
  # IMPLEMENTATION - User backup service
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    
    # Validation assertions
    assertions = [
      {
        assertion = cfg.externalDrive.enable || cfg.protonDrive.enable;
        message = "At least one backup method must be enabled (externalDrive or protonDrive)";
      }
      {
        assertion = !cfg.protonDrive.enable || !cfg.protonDrive.useSecret || (config.age.secrets ? "${cfg.protonDrive.secretName}");
        message = "Proton Drive secret '${cfg.protonDrive.secretName}' not found but useSecret is enabled";
      }
      {
        assertion = config.hwc.system.users.enable;
        message = "User backup requires hwc.system.users.enable = true";
      }
    ];
    
    # Backup script is used directly by systemd service
    
    # Rclone config from agenix secret
    environment.etc."rclone-proton.conf" = lib.mkIf (cfg.protonDrive.enable && cfg.protonDrive.useSecret) {
      source = config.age.secrets.${cfg.protonDrive.secretName}.path;
      mode = "0600";
    };
    
    # Backup service
    systemd.services.user-backup = {
      description = "User data backup service";
      wants = lib.optionals cfg.protonDrive.enable [ "network-online.target" ];
      after = [ "local-fs.target" ] ++ lib.optionals cfg.protonDrive.enable [ "network-online.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";  # Needed to access user files and mount points
        ExecStart = backupScript;
        
        # Security hardening
        PrivateTmp = true;
        NoNewPrivileges = true;
        
        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };
      
      # Only run if scheduling is disabled (manual runs)
      wantedBy = lib.mkIf (!cfg.schedule.enable) [ "multi-user.target" ];
    };
    
    # Backup timer for scheduled runs
    systemd.timers.user-backup = lib.mkIf cfg.schedule.enable {
      description = "User backup timer";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = cfg.schedule.frequency;
        RandomizedDelaySec = cfg.schedule.randomDelay;
        Persistent = true;
        
        # Ensure we don't run backups too frequently
        AccuracySec = "1h";
      };
    };
    
    # Log rotation for backup logs
    services.logrotate.settings.user-backup = {
      files = [ "/var/log/user-backup.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
    
    # Warning when both methods are disabled
    warnings = lib.optionals (!cfg.externalDrive.enable && !cfg.protonDrive.enable) [
      "User backup service is enabled but no backup methods are configured"
    ];
  };
}