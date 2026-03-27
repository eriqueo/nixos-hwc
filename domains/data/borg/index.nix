# domains/system/services/borg/index.nix
#
# BORG BACKUP - Deduplicating encrypted backup service
#
# Charter v10.3 compliant module providing:
# - Block-level deduplication (efficient for incremental backups)
# - Client-side encryption (repokey-blake2)
# - Automatic pruning with configurable retention
# - Pre/post backup hooks for database dumps
#
# Namespace: hwc.data.borg.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.data.borg;
  paths = config.hwc.paths;
  enabled = cfg.enable;

  # Job name for systemd service
  jobName = "hwc-backup";

  # Build OnCalendar string
  onCalendar =
    if cfg.schedule.frequency == "daily" then
      "*-*-* ${cfg.schedule.timeOfDay}:00"
    else if cfg.schedule.frequency == "weekly" then
      "Mon *-*-* ${cfg.schedule.timeOfDay}:00"
    else
      "${cfg.schedule.frequency} *-*-* ${cfg.schedule.timeOfDay}:00";

in
{
  # OPTIONS
  options.hwc.data.borg = {
    enable = lib.mkEnableOption "Borg deduplicating backup service";

    #==========================================================================
    # REPOSITORY CONFIGURATION
    #==========================================================================
    repo = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "${toString paths.backup}/borg";
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

      healthCheck = {
        enable = lib.mkEnableOption "Daily backup health check with ntfy notifications";

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "06:00";
          description = "Time of day to run health check (HH:MM, Mountain Time)";
        };

        ntfyTopic = lib.mkOption {
          type = lib.types.str;
          default = "alerts";
          description = "ntfy topic for backup health notifications";
        };

        maxBackupAgeHours = lib.mkOption {
          type = lib.types.int;
          default = 26;
          description = "Alert if last backup is older than this many hours";
        };

        maxRunTimeHours = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Alert if any borg process has been running longer than this";
        };

        zfsPool = lib.mkOption {
          type = lib.types.str;
          default = "backup-pool";
          description = "ZFS pool to check for health status";
        };
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

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {

    # Borg package + helper scripts
    environment.systemPackages = [
      pkgs.borgbackup

      # borg-hwc: wrapper with passphrase pre-loaded
      (pkgs.writeShellScriptBin "borg-hwc" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        export BORG_REPO="${cfg.repo.path}"
        exec ${pkgs.borgbackup}/bin/borg "$@"
      '')

      # borg-list: show recent backups
      (pkgs.writeShellScriptBin "borg-list" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        echo "=== Borg Archives ==="
        ${pkgs.borgbackup}/bin/borg list "${cfg.repo.path}"
        echo ""
        echo "=== Repository Info ==="
        ${pkgs.borgbackup}/bin/borg info "${cfg.repo.path}"
      '')

      # borg-restore: restore files from archive
      (pkgs.writeShellScriptBin "borg-restore" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        if [ $# -lt 2 ]; then
          echo "Usage: borg-restore <archive-name> <target-dir> [path]"
          echo ""
          echo "Examples:"
          echo "  borg-restore hwc-server-hwc-backup-2026-03-02 /tmp/restore"
          echo "  borg-restore hwc-server-hwc-backup-2026-03-02 /tmp/restore var/lib/hwc/n8n"
          echo ""
          echo "Available archives:"
          ${pkgs.borgbackup}/bin/borg list --short "${cfg.repo.path}"
          exit 1
        fi
        ARCHIVE="$1"; TARGET="$2"; SUBPATH="''${3:-.}"
        mkdir -p "$TARGET" && cd "$TARGET"
        ${pkgs.borgbackup}/bin/borg extract "${cfg.repo.path}::$ARCHIVE" "$SUBPATH"
        echo "Restored to $TARGET"
      '')

      # borg-backup-now: trigger manual backup
      (pkgs.writeShellScriptBin "borg-backup-now" ''
        echo "Starting Borg backup..."
        sudo systemctl start borgbackup-job-${jobName}.service
        echo "Check status: journalctl -fu borgbackup-job-${jobName}.service"
      '')
    ];

    # Borg backup job using NixOS module
    services.borgbackup.jobs.${jobName} = {
      # What to back up
      paths = cfg.sources;
      exclude = cfg.excludePatterns;

      # Repository
      repo = cfg.repo.path;

      # Encryption
      encryption = {
        mode = cfg.encryption.mode;
        passCommand = "cat /run/agenix/${cfg.encryption.passphraseSecret}";
      };

      # Compression
      compression = cfg.compression;

      # Schedule
      startAt = []; # We use our own timer for more control

      # Pre-backup hook (database dumps, etc.)
      preHook = lib.mkIf (cfg.preBackupScript != null) cfg.preBackupScript;

      # Post-backup hook
      postHook = lib.mkIf (cfg.postBackupScript != null) cfg.postBackupScript;

      # Retention policy (pruning)
      prune.keep = {
        daily = cfg.retention.daily;
        weekly = cfg.retention.weekly;
        monthly = cfg.retention.monthly;
      } // lib.optionalAttrs (cfg.retention.yearly > 0) {
        yearly = cfg.retention.yearly;
      };

      # Environment for hooks
      environment = {
        BORG_RSH = "ssh -o StrictHostKeyChecking=accept-new";
      };

      # Read-write paths for pre/post hooks
      readWritePaths = [
        "/var/lib/backups"
        cfg.repo.path
      ];
    };

    # Custom timer with random delay support
    systemd.timers."borgbackup-job-${jobName}" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        RandomizedDelaySec = cfg.schedule.randomDelay;
        Persistent = true;
      };
    };

    # Failure notification + better timeout handling
    systemd.services."borgbackup-job-${jobName}" = {
      onFailure = lib.mkIf (cfg.notifications.onFailure && (config.hwc.alerts.enable or false)) [
        "hwc-service-failure-notifier@borgbackup-job-${jobName}.service"
      ];
      # Prevent stuck borg processes from blocking future backups
      serviceConfig = {
        TimeoutStartSec = "4h";        # Kill backup if stuck longer than 4 hours
        TimeoutStopSec = "5min";       # Give borg time to finish gracefully
        KillMode = "mixed";            # SIGTERM to main, SIGKILL to remaining after timeout
        KillSignal = "SIGINT";         # Borg handles SIGINT gracefully (checkpoint)
      };
    };

    # Repository integrity check timer
    systemd.services.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Borg repository integrity check";
      # Don't restart on nixos-rebuild - this runs for hours and blocks switch-to-configuration
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.borgbackup}/bin/borg check ${cfg.repo.path}";
        Environment = "BORG_PASSCOMMAND=cat /run/agenix/${cfg.encryption.passphraseSecret}";
        TimeoutStartSec = "6h";  # Kill if stuck longer than 6 hours
      };
    };

    systemd.timers.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Weekly Borg repository check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.monitoring.checkFrequency;
        Persistent = true;
      };
    };

    # ===================================================================
    # BACKUP HEALTH CHECK (daily ntfy notification)
    # ===================================================================
    systemd.services.borg-health-check = lib.mkIf cfg.monitoring.healthCheck.enable {
      description = "Borg backup health check with ntfy notification";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.systemd
        pkgs.coreutils
        pkgs.gawk
        pkgs.procps
        pkgs.ripgrep
        pkgs.zfs
        pkgs.smartmontools
        pkgs.curl
        pkgs.nettools
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          hc = cfg.monitoring.healthCheck;
          healthScript = pkgs.writeShellScript "borg-health-check" ''
            set -uo pipefail

            NTFY_TOPIC="${hc.ntfyTopic}"
            MAX_AGE_HOURS=${toString hc.maxBackupAgeHours}
            MAX_RUN_HOURS=${toString hc.maxRunTimeHours}
            MAX_RUN_SECS=$((MAX_RUN_HOURS * 3600))
            ZFS_POOL="${hc.zfsPool}"
            PROBLEMS=()

            # 1. Timer active?
            if ! systemctl is-active --quiet borgbackup-job-${jobName}.timer; then
              PROBLEMS+=("Backup timer is not active")
            fi

            # 2. Service failed?
            if systemctl is-failed --quiet borgbackup-job-${jobName}.service; then
              PROBLEMS+=("Backup service is in failed state")
            fi

            # 3. Last completion age
            AGE_HOURS="unknown"
            LAST_EXIT=$(systemctl show borgbackup-job-${jobName}.service --property=ExecMainExitTimestamp --value)
            if [ -n "$LAST_EXIT" ] && [ "$LAST_EXIT" != "" ]; then
              LAST_EPOCH=$(date -d "$LAST_EXIT" +%s 2>/dev/null || echo "0")
              if [ "$LAST_EPOCH" -gt 0 ]; then
                NOW_EPOCH=$(date +%s)
                AGE_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))
                if [ "$AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
                  PROBLEMS+=("Last backup was ''${AGE_HOURS}h ago (threshold: ''${MAX_AGE_HOURS}h)")
                fi
              else
                PROBLEMS+=("Cannot parse last backup completion time")
              fi
            else
              PROBLEMS+=("Cannot determine last backup completion time")
            fi

            # 4. Stuck borg process (>MAX_RUN_HOURS)
            STUCK=$(ps -eo pid,etimes,comm 2>/dev/null | rg borg | awk -v max="$MAX_RUN_SECS" '$2 > max {printf "%s (running %dh) ", $1, $2/3600}')
            if [ -n "$STUCK" ]; then
              PROBLEMS+=("Stuck borg process: $STUCK")
            fi

            # 5. ZFS pool health
            POOL_HEALTH=$(zpool get -H -o value health "$ZFS_POOL" 2>/dev/null || echo "UNKNOWN")
            if [ "$POOL_HEALTH" != "ONLINE" ]; then
              PROBLEMS+=("$ZFS_POOL is $POOL_HEALTH (expected ONLINE)")
            fi

            # 6. SMART warnings on backup drives
            for dev in $(zpool status "$ZFS_POOL" 2>/dev/null | rg -o '/dev/[^ ]+' | sort -u); do
              # Resolve disk/by-id symlinks to actual device for smartctl
              REAL_DEV=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
              REALLOC=$(smartctl -A "$REAL_DEV" 2>/dev/null | rg "Reallocated_Sector" | awk '{print $NF}')
              PENDING=$(smartctl -A "$REAL_DEV" 2>/dev/null | rg "Current_Pending" | awk '{print $NF}')
              if [ "''${REALLOC:-0}" -gt 0 ] 2>/dev/null || [ "''${PENDING:-0}" -gt 0 ] 2>/dev/null; then
                PROBLEMS+=("Drive $REAL_DEV: ''${REALLOC:-0} reallocated, ''${PENDING:-0} pending sectors")
              fi
            done

            # Send notification via hwc-ntfy-send
            if [ ''${#PROBLEMS[@]} -gt 0 ]; then
              MSG=$(printf '• %s\n' "''${PROBLEMS[@]}")
              hwc-ntfy-send \
                --tag "rotating_light,backup" \
                --priority 5 \
                "$NTFY_TOPIC" \
                "Backup ALERT" \
                "Backup health check failed:
$MSG"
              exit 1
            else
              hwc-ntfy-send \
                --tag "white_check_mark,backup" \
                --priority 2 \
                "$NTFY_TOPIC" \
                "Backup OK" \
                "Backup healthy — last completed ''${AGE_HOURS}h ago, pool $POOL_HEALTH"
            fi
          '';
        in "${healthScript}";
      };
    };

    systemd.timers.borg-health-check = lib.mkIf cfg.monitoring.healthCheck.enable {
      description = "Daily backup health check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.monitoring.healthCheck.schedule}:00 America/Denver";
        Persistent = true;
      };
    };

    # Ensure backup directory structure exists
    systemd.tmpfiles.rules = [
      "d /var/lib/backups 0750 root root -"
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.sources != [];
        message = "hwc.data.borg.sources must not be empty";
      }
      {
        assertion = cfg.encryption.mode != "none" || cfg.repo.remote.enable == false;
        message = "Remote Borg repositories must use encryption";
      }
    ];

    warnings = lib.optionals (cfg.encryption.mode == "none") [
      "Borg backup encryption is disabled. This is not recommended for sensitive data."
    ];
  };
}
