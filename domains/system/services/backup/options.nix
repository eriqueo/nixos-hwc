# domains/system/services/backup/options.nix
# Comprehensive backup system for NixOS with local and cloud backup support
{ lib, config, ... }:

{
  options.hwc.system.services.backup = {
    enable = lib.mkEnableOption "Enable the system-wide backup service";

    #==========================================================================
    # LOCAL BACKUP CONFIGURATION (External drives, NAS, DAS)
    #==========================================================================
    local = {
      enable = lib.mkEnableOption "Enable local backup to external drives/NAS/DAS";

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/backup";
        description = "Mount point for the backup destination (external drive, NAS, or DAS)";
      };

      useRsync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use rsync for incremental backups (faster, space-efficient)";
      };

      keepDaily = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of daily backups to keep";
      };

      keepWeekly = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Number of weekly backups to keep";
      };

      keepMonthly = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Number of monthly backups to keep";
      };

      minSpaceGB = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Minimum free space required (GB) before attempting backup";
      };

      sources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/home" "/etc/nixos" ];
        description = "Directories to backup";
      };

      excludePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          ".cache"
          "*.tmp"
          "*.temp"
          ".local/share/Trash"
          "node_modules"
          "__pycache__"
          ".npm"
          ".cargo/registry"
          ".cargo/git"
        ];
        description = "Patterns to exclude from backup";
      };
    };

    #==========================================================================
    # CLOUD BACKUP CONFIGURATION (Proton Drive)
    #==========================================================================
    cloud = {
      enable = lib.mkEnableOption "Enable cloud backup (fallback or primary)";

      provider = lib.mkOption {
        type = lib.types.enum [ "proton-drive" "custom" ];
        default = "proton-drive";
        description = "Cloud storage provider";
      };

      remotePath = lib.mkOption {
        type = lib.types.str;
        default = "Backups";
        description = "Remote path on cloud storage";
      };

      syncMode = lib.mkOption {
        type = lib.types.enum [ "sync" "copy" "move" ];
        default = "sync";
        description = "Rclone mode: sync (mirror), copy (one-way), or move";
      };

      bandwidthLimit = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10M";
        description = "Bandwidth limit for cloud uploads (e.g., '10M' for 10 MB/s)";
      };
    };

    protonDrive = {
      enable = lib.mkEnableOption "Enable Proton Drive as a backup target";

      secretName = lib.mkOption {
        type = lib.types.str;
        default = "rclone-proton-config";
        description = "Name of the agenix secret containing the rclone config for Proton Drive.";
      };
    };

    #==========================================================================
    # SCHEDULING CONFIGURATION
    #==========================================================================
    schedule = {
      enable = lib.mkEnableOption "Enable automatic backup scheduling";

      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Backup frequency (systemd calendar format: daily, weekly, Mon-Fri, etc.)";
      };

      timeOfDay = lib.mkOption {
        type = lib.types.str;
        default = "02:00";
        description = "Time of day to run backup (HH:MM format)";
      };

      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Random delay to spread backup load";
      };

      onlyOnAC = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Only run backups when on AC power (laptops)";
      };
    };

    #==========================================================================
    # NOTIFICATION CONFIGURATION
    #==========================================================================
    notifications = {
      enable = lib.mkEnableOption "Enable desktop notifications for backup status";

      onSuccess = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Show notification on successful backup";
      };

      onFailure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show notification on backup failure";
      };
    };

    #==========================================================================
    # MONITORING CONFIGURATION
    #==========================================================================
    monitoring = {
      enable = lib.mkEnableOption "Enable backup monitoring and maintenance tools";

      logPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/log/backup";
        description = "Directory for backup logs";
      };

      healthCheckInterval = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "How often to run backup health checks";
      };
    };

    #==========================================================================
    # ADVANCED OPTIONS
    #==========================================================================
    extraTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional backup-related packages to install.";
    };

    preBackupScript = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Script to run before backup starts";
    };

    postBackupScript = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Script to run after backup completes";
    };
  };
}
