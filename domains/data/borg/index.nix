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

      # Don't fail on borg warnings (exit 1) like "file changed during backup"
      failOnWarnings = false;

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

      # Reduce compact I/O — only rewrite segments with >25% freed space (default 10%)
      extraCompactArgs = [ "--threshold" "25" ];

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
      onFailure = lib.mkIf (cfg.notifications.onFailure && (config.hwc.monitoring.alerts.enable or false)) [
        "hwc-service-failure-notifier@borgbackup-job-${jobName}.service"
      ];
      # Don't kill running backups on nixos-rebuild switch
      restartIfChanged = false;
      # Wait up to 1h for lock instead of failing immediately
      environment.BORG_LOCK_WAIT = "3600";
      # Don't run backup while borg-check is running
      conflicts = [ "borg-check.service" ];
      after = [ "borg-check.service" ];
      # Break stale locks before starting (from previous crashes/kills)
      preStart = ''
        ${pkgs.borgbackup}/bin/borg break-lock ${cfg.repo.path} 2>/dev/null || true
      '';
      # Prevent stuck borg processes from blocking future backups
      serviceConfig = {
        Type = "oneshot";              # Backup runs to completion, not a long-lived daemon
        TimeoutStartSec = "12h";      # Allow up to 12h (compact can be slow on large repos)
        CPUSchedulingPolicy = lib.mkForce "other";  # Best-effort (default) instead of idle
        IOSchedulingClass = lib.mkForce "best-effort";  # Fair I/O instead of idle scraps
        TimeoutStopSec = "5min";      # Give borg time to finish gracefully
        KillMode = "mixed";            # SIGTERM to main, SIGKILL to remaining after timeout
        KillSignal = "SIGINT";         # Borg handles SIGINT gracefully (checkpoint)
      };
    };

    # Repository integrity check timer
    systemd.services.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Borg repository integrity check";
      # Don't restart on nixos-rebuild - this runs for hours and blocks switch-to-configuration
      restartIfChanged = false;
      # Use environment attr so NixOS quotes it properly for systemd
      environment.BORG_PASSCOMMAND = "cat /run/agenix/${cfg.encryption.passphraseSecret}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.borgbackup}/bin/borg check ${cfg.repo.path}";
      };
    };

    systemd.timers.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Weekly Borg repository check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Run Sunday noon — well away from the 02:00-03:00 backup window
        OnCalendar = "Sun *-*-* 12:00:00";
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
