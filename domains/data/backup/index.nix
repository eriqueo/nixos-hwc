# domains/data/backup/index.nix
#
# Backup domain — system-wide backup service and tools.
# Supports local backups (external drives, NAS, DAS), cloud backups (Proton Drive),
# user data backup, and server container/database backup scripts.
#
# Namespace: hwc.data.backup.*
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.data.backup;
in
{
  # OPTIONS
  options.hwc.data.backup = {
    enable = lib.mkEnableOption "Enable the system-wide backup service";

    #==========================================================================
    # LOCAL BACKUP CONFIGURATION (External drives, NAS, DAS)
    #==========================================================================
    local = {
      enable = lib.mkEnableOption "Enable local backup to external drives/NAS/DAS";

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = config.hwc.paths.backup or "/mnt/backup";
        description = "Mount point for the backup destination (external drive, NAS, or DAS)";
      };

      useRsync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use rsync for incremental backups (faster, space-efficient)";
      };

      keepDaily = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Count of daily backups to keep (newest retained)";
      };

      keepWeekly = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Count of weekly backups to keep (newest retained)";
      };

      keepMonthly = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Count of monthly backups to keep (newest retained)";
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

      # gotify integration for cross-machine notifications
      gotify = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable gotify notifications (requires hwc.notifications.send.gotify.enable)";
        };

        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to gotify app token file for backup notifications";
        };

        onSuccess = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Send gotify notification on successful backup";
        };

        onFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Send gotify notification on backup failure";
        };
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

    #==========================================================================
    # DATABASE CONSISTENCY OPTIONS
    #==========================================================================
    database = {
      postgres = {
        enable = lib.mkEnableOption "PostgreSQL consistent backups (pg_basebackup + WAL)";

        pitr = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Point-In-Time Recovery with WAL archiving";
        };
      };

      mysql = {
        enable = lib.mkEnableOption "MySQL/MariaDB consistent backups";
      };

      redis = {
        enable = lib.mkEnableOption "Redis RDB snapshots";
      };

      docker = {
        enable = lib.mkEnableOption "Docker volume backups";
      };
    };

    #==========================================================================
    # ENCRYPTION OPTIONS
    #==========================================================================
    encryption = {
      local = {
        enable = lib.mkEnableOption "Encrypt local backups at rest";

        method = lib.mkOption {
          type = lib.types.enum [ "luks" "gocryptfs" "rclone-crypt" ];
          default = "luks";
          description = "Encryption method for local backups";
        };

        luksDevice = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/dev/disk/by-uuid/...";
          description = "LUKS device path (if using LUKS encryption)";
        };
      };

      cloud = {
        enable = lib.mkEnableOption "Encrypt cloud backups (client-side)";

        password = {
          useSecret = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Use agenix secret for encryption password";
          };

          secretName = lib.mkOption {
            type = lib.types.str;
            default = "backup-encryption-password";
            description = "Name of agenix secret containing encryption password";
          };
        };
      };
    };
  };

  imports = [
    ./parts/local-backup.nix
    ./parts/cloud-backup.nix
    ./parts/backup-utils.nix
    ./parts/backup-scheduler.nix
    ./parts/database-hooks.nix
    ./parts/server-backup-scripts.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rclone
      rsync
      gnutar
      gzip
      bzip2
      p7zip
      logrotate
      findutils
      coreutils
      util-linux
      gawk
      gnused
      gnugrep
      nettools
      libnotify
    ]
    ++ cfg.extraTools;

    warnings = lib.optionals (!cfg.local.enable && !cfg.cloud.enable) [
      "Backup service is enabled but no backup methods (local or cloud) are configured"
    ];
  };
}
