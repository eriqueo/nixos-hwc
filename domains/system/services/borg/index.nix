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
# Namespace: hwc.system.services.borg.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.borg;
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
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {

    # Borg package
    environment.systemPackages = [ pkgs.borgbackup ];

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

    # Failure notification via alerts domain (if available)
    systemd.services."borgbackup-job-${jobName}" = {
      onFailure = lib.mkIf (cfg.notifications.onFailure && (config.hwc.alerts.enable or false)) [
        "hwc-service-failure-notifier@borgbackup-job-${jobName}.service"
      ];
    };

    # Repository integrity check timer
    systemd.services.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Borg repository integrity check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.borgbackup}/bin/borg check ${cfg.repo.path}";
        Environment = "BORG_PASSCOMMAND=cat /run/agenix/${cfg.encryption.passphraseSecret}";
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
        message = "hwc.system.services.borg.sources must not be empty";
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
