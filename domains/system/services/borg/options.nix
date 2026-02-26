# domains/system/services/borg/options.nix
# Borg Backup - Deduplicating backup with encryption
#
# Namespace: hwc.system.services.borg.*

{ lib, config, ... }:

{
  options.hwc.system.services.borg = {
    enable = lib.mkEnableOption "Borg deduplicating backup service";

    #==========================================================================
    # REPOSITORY CONFIGURATION
    #==========================================================================
    repo = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/backup/borg";
        description = "Path to local Borg repository";
      };

      # Future: remote repository support
      remote = {
        enable = lib.mkEnableOption "Remote repository (SSH)";

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "user@backup-server:/path/to/repo";
          description = "SSH path to remote Borg repository";
        };
      };
    };

    #==========================================================================
    # BACKUP SOURCES
    #==========================================================================
    sources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "/home" "/var/lib/data" ];
      description = "Directories to back up";
    };

    excludePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/nix"
        ".cache"
        "*.tmp"
        "*.temp"
        "node_modules"
        "__pycache__"
        ".local/share/Trash"
      ];
      description = "Patterns to exclude from backup";
    };

    #==========================================================================
    # ENCRYPTION
    #==========================================================================
    encryption = {
      mode = lib.mkOption {
        type = lib.types.enum [ "repokey" "repokey-blake2" "keyfile" "keyfile-blake2" "none" ];
        default = "repokey-blake2";
        description = "Encryption mode (repokey-blake2 recommended)";
      };

      passphraseSecret = lib.mkOption {
        type = lib.types.str;
        default = "borg-passphrase";
        description = "Name of agenix secret containing the passphrase";
      };
    };

    #==========================================================================
    # COMPRESSION
    #==========================================================================
    compression = lib.mkOption {
      type = lib.types.str;
      default = "auto,zstd";
      example = "lz4";
      description = "Compression algorithm (auto,zstd recommended for mixed content)";
    };

    #==========================================================================
    # SCHEDULING
    #==========================================================================
    schedule = {
      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        example = "Mon,Thu,Sun";
        description = "Backup frequency (systemd calendar format)";
      };

      timeOfDay = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time of day to run backup (HH:MM)";
      };

      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Random delay to spread load";
      };
    };

    #==========================================================================
    # RETENTION (PRUNING)
    #==========================================================================
    retention = {
      daily = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of daily archives to keep";
      };

      weekly = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Number of weekly archives to keep";
      };

      monthly = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Number of monthly archives to keep";
      };

      yearly = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Number of yearly archives to keep (0 to disable)";
      };
    };

    #==========================================================================
    # HOOKS
    #==========================================================================
    preBackupScript = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Script to run before backup (e.g., database dumps)";
    };

    postBackupScript = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Script to run after successful backup";
    };

    #==========================================================================
    # MONITORING
    #==========================================================================
    monitoring = {
      enable = lib.mkEnableOption "Backup monitoring and health checks";

      checkFrequency = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "How often to run borg check";
      };
    };

    #==========================================================================
    # NOTIFICATIONS
    #==========================================================================
    notifications = {
      onFailure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Send notification on backup failure";
      };

      onSuccess = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Send notification on backup success";
      };
    };
  };
}
