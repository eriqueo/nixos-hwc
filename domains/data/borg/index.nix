# domains/data/borg/index.nix
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
  snapshots = lib.mapAttrsToList (name: value: value // { inherit name; }) cfg.sqliteSnapshots;
  snapshotRoot = "${paths.state}/borg-sqlite";
  snapshotReady = "${snapshotRoot}/ready";
  snapshotPackage = pkgs.writeShellScriptBin "borg-sqlite-snapshot" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux pkgs.python3 ]}
    exec ${pkgs.python3}/bin/python3 ${./sqlite-snapshot.py} "$@"
  '';
  sqliteBackup = lib.concatMapStrings (value: ''
    ${snapshotPackage}/bin/borg-sqlite-snapshot create \
      --state-root ${lib.escapeShellArg snapshotRoot} --name ${lib.escapeShellArg value.name} \
      --source ${lib.escapeShellArg value.source} --user ${lib.escapeShellArg value.user} \
      --max-bytes ${toString value.maxBytes} --timeout-seconds ${toString value.timeoutSeconds} || exit "$?"
  '') snapshots;
  snapshotExcludes = lib.concatMap (value: map (suffix: "pf:${value.source}${suffix}")
    [ "" "-wal" "-shm" ]) snapshots
    ++ lib.optional (snapshots != []) "pp:${snapshotRoot}/staging";
  snapshotSources = lib.optional (snapshots != [] && !(lib.any
    (source: source == snapshotReady || lib.hasPrefix "${lib.removeSuffix "/" source}/" snapshotReady)
    cfg.sources)) snapshotReady;

  # Job name for systemd service
  jobName = "hwc-backup";

  # One producer for "where the repository is": local path or SSH URL.
  repoUrl = if cfg.repo.remote.enable then cfg.repo.remote.path else cfg.repo.path;

  # SSH command for the job and the interactive wrappers. The key flag is
  # present only when a remote key secret is named.
  borgRsh = "ssh -o StrictHostKeyChecking=accept-new"
    + lib.optionalString (cfg.repo.remote.enable && cfg.repo.remote.sshKeySecret != null)
        " -i /run/agenix/${cfg.repo.remote.sshKeySecret}";

  # CRITICAL: logical PostgreSQL snapshots. One producer for every Borg host;
  # use the running cluster's package, never the unrelated CLI package in PATH.
  # Publish atomically and abort the backup if the producer fails. Retain 14
  # days locally; Borg owns long-term retention. Nested migration archives are
  # deliberately outside this cleanup boundary.
  postgresBackup = lib.optionalString config.services.postgresql.enable ''
    (
      set -euo pipefail
      umask 077
      dumpDir=/var/lib/backups
      mkdir -p "$dumpDir" || exit 1
      dumpFile="$dumpDir/postgresql-$(date +%Y-%m-%d).sql.gz"
      dumpTemp=$(mktemp "$dumpDir/.postgresql-XXXXXX") || exit 1
      trap 'rm -f "$dumpTemp"' EXIT
      /run/wrappers/bin/su - postgres -s /bin/sh -c '${config.services.postgresql.package}/bin/pg_dumpall' \
        | ${pkgs.gzip}/bin/gzip --rsyncable > "$dumpTemp" || exit 1
      ${pkgs.gzip}/bin/gzip -t "$dumpTemp" || exit 1
      mv "$dumpTemp" "$dumpFile" || exit 1
      find "$dumpDir" -maxdepth 1 -name 'postgresql-*.sql.gz' -mtime +14 -delete
    ) || exit "$?"
  '';

  destinations = cfg.additionalDestinations;
  lockRoot = "${paths.state}/borg-jobs";
  serializationHook = lib.optionalString (destinations != {}) ''
    exec 9>${lib.escapeShellArg "${lockRoot}/snapshot-archive.lock"}
    ${pkgs.util-linux}/bin/flock --wait 300 9 || exit "$?"
  '';
  destinationJobName = name: "${jobName}-${name}";
  destinationCheckName = name: "borg-check-${name}";
  destinationCredential = target: "borg-ssh-key:${config.hwc.secrets.api.${target.sshKeySecret}}";
  destinationRsh = name: target:
    let knownHosts = pkgs.writeText "borg-${name}-known-hosts" "${target.host} ${target.hostKey}\n";
    in toString (pkgs.writeShellScript "borg-${name}-ssh" ''
      set -eu
      test -r "$CREDENTIALS_DIRECTORY/borg-ssh-key"
      exec ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile=${knownHosts} -o ConnectTimeout=15 \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -i "$CREDENTIALS_DIRECTORY/borg-ssh-key" "$@"
    '');
  destinationUrl = target: "ssh://${target.user}@${target.host}${target.repository}";
  destinationJobs = lib.mapAttrs' (name: target: lib.nameValuePair (destinationJobName name)
    (backupJob // {
      repo = destinationUrl target;
      encryption = { mode = cfg.encryption.mode; passCommand = "cat ${config.hwc.secrets.api.${target.passphraseSecret}}"; };
      environment.BORG_RSH = destinationRsh name target;
      # An SSH URL must never enter ReadWritePaths.
      # Include application-provided writable snapshot paths (for example Meals)
      # while excluding the primary local repository from the remote job.
      readWritePaths = lib.filter (path: cfg.repo.remote.enable || path != cfg.repo.path)
        config.services.borgbackup.jobs.${jobName}.readWritePaths;
    })) destinations;

  backupJob = {
    # What to back up
    paths = cfg.sources ++ snapshotSources;
    exclude = cfg.excludePatterns ++ snapshotExcludes;

    # Repository (local path or SSH URL)
    repo = repoUrl;

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
    preHook = serializationHook + postgresBackup + sqliteBackup + lib.optionalString (cfg.preBackupScript != null) cfg.preBackupScript;

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

    # Environment for hooks and the remote transport
    environment = {
      BORG_RSH = borgRsh;
    };

    # Read-write paths for pre/post hooks. A remote repo is not a path.
    readWritePaths = [
      "/var/lib/backups"
    ] ++ lib.optional (destinations != {}) lockRoot
      ++ lib.optional (snapshots != []) snapshotRoot
      ++ lib.optional (!cfg.repo.remote.enable) cfg.repo.path;
  };

  jobService = {
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
    # Respect readers and other writers. A stale lock is an operator recovery
    # action after checking its holder, never an automatic startup step.
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

      # Remote repository over SSH. When enabled, `remote.path` replaces
      # `repo.path` everywhere (job, wrappers, check, break-lock) and is kept
      # out of ReadWritePaths, which only accepts filesystem paths. The
      # serving host declares the matching `services.borgbackup.repos.<name>`
      # with the client's public key, so `borg serve` is restricted to that
      # one repository.
      remote = {
        enable = lib.mkEnableOption "Remote repository (SSH)";

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "ssh://borg@100.77.195.118/mnt/backup/borg-hwc-work";
          description = "SSH URL of the remote Borg repository";
        };

        sshKeySecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "borg-work-ssh-key";
          description = ''
            Name of the agenix secret holding the private SSH key the root-run
            backup job presents to the remote host. Mount it 0400 root, since
            OpenSSH refuses a key any group can read.
          '';
        };
      };
    };

    additionalDestinations = lib.mkOption {
      default = {};
      description = "Independent encrypted SSH repositories. No targets by default; at most four. Each native job uses the shared sources and snapshot producer under a 300-second host lock. Retention follows the primary policy.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          host = lib.mkOption { type = lib.types.str; description = "Pinned SSH hostname or IPv4 address"; };
          user = lib.mkOption { type = lib.types.str; default = "borg"; description = "Restricted storage account"; };
          repository = lib.mkOption { type = lib.types.str; description = "Absolute remote repository path"; };
          hostKey = lib.mkOption { type = lib.types.str; description = "Pinned public SSH host key (algorithm and base64)"; };
          sshKeySecret = lib.mkOption { type = lib.types.str; description = "Agenix SSH identity delivered privately through systemd LoadCredential"; };
          passphraseSecret = lib.mkOption { type = lib.types.str; description = "Independent agenix encryption passphrase"; };
          startAt = lib.mkOption { type = lib.types.str; description = "Independent systemd calendar schedule"; };
          checkAt = lib.mkOption { type = lib.types.str; default = "Sun *-*-* 14:00:00"; description = "Repository consistency-check calendar; full cryptographic verification is a separate recovery acceptance step"; };
        };
      });
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

    sqliteSnapshots = lib.mkOption {
      default = {};
      description = "CRITICAL SQLite online snapshots; one last-good file and one bounded staging slot per name. Failure aborts Borg. Restore ready/<name>.sqlite, not raw live database files.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          source = lib.mkOption { type = lib.types.str; description = "Absolute physical SQLite source path, owned by user"; };
          user = lib.mkOption { type = lib.types.str; description = "Existing application user for the readonly source worker"; };
          maxBytes = lib.mkOption { type = lib.types.ints.between 1 68719476736; default = 8589934592; description = "Maximum bytes per snapshot (default 8 GiB)"; };
          timeoutSeconds = lib.mkOption { type = lib.types.ints.between 1 3600; default = 600; description = "Deadline for snapshot and validation"; };
        };
      });
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
  config = lib.mkIf enabled (lib.mkMerge [ {

    # Borg package + helper scripts
    environment.systemPackages = [
      pkgs.borgbackup

      # borg-hwc: wrapper with passphrase pre-loaded
      (pkgs.writeShellScriptBin "borg-hwc" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        export BORG_RSH="${borgRsh}"
        export BORG_REPO="${repoUrl}"
        exec ${pkgs.borgbackup}/bin/borg "$@"
      '')

      # borg-list: show recent backups
      (pkgs.writeShellScriptBin "borg-list" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        export BORG_RSH="${borgRsh}"
        echo "=== Borg Archives ==="
        ${pkgs.borgbackup}/bin/borg list "${repoUrl}"
        echo ""
        echo "=== Repository Info ==="
        ${pkgs.borgbackup}/bin/borg info "${repoUrl}"
      '')

      # borg-restore: restore files from archive
      (pkgs.writeShellScriptBin "borg-restore" ''
        export BORG_PASSCOMMAND="cat /run/agenix/${cfg.encryption.passphraseSecret}"
        export BORG_RSH="${borgRsh}"
        if [ $# -lt 2 ]; then
          echo "Usage: borg-restore <archive-name> <target-dir> [path]"
          echo ""
          echo "Examples:"
          echo "  borg-restore hwc-server-hwc-backup-2026-03-02 /tmp/restore"
          echo "  borg-restore hwc-server-hwc-backup-2026-03-02 /tmp/restore var/lib/hwc/n8n"
          echo ""
          echo "Available archives:"
          ${pkgs.borgbackup}/bin/borg list --short "${repoUrl}"
          exit 1
        fi
        ARCHIVE="$1"; TARGET="$2"; SUBPATH="''${3:-.}"
        mkdir -p "$TARGET" && cd "$TARGET" || exit 1
        exec ${pkgs.borgbackup}/bin/borg extract "${repoUrl}::$ARCHIVE" "$SUBPATH"
      '')

      # borg-backup-now: trigger manual backup
      (pkgs.writeShellScriptBin "borg-backup-now" ''
        echo "Starting Borg backup..."
        sudo systemctl start borgbackup-job-${jobName}.service
        echo "Check status: journalctl -fu borgbackup-job-${jobName}.service"
      '')
    ] ++ lib.optional (snapshots != []) snapshotPackage;

    # The primary job retains its established name and machine overrides.
    services.borgbackup.jobs.${jobName} = backupJob;

    # Custom timer with random delay support
    systemd.timers."borgbackup-job-${jobName}" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        RandomizedDelaySec = cfg.schedule.randomDelay;
        Persistent = true;
      };
    };

    systemd.services."borgbackup-job-${jobName}" = jobService;

    # Repository integrity check timer
    systemd.services.borg-check = lib.mkIf cfg.monitoring.enable {
      description = "Borg repository integrity check";
      # Don't restart on nixos-rebuild - this runs for hours and blocks switch-to-configuration
      restartIfChanged = false;
      # Use environment attr so NixOS quotes it properly for systemd
      environment.BORG_PASSCOMMAND = "cat /run/agenix/${cfg.encryption.passphraseSecret}";
      environment.BORG_RSH = borgRsh;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.borgbackup}/bin/borg check ${repoUrl}";
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
    ] ++ lib.optionals (snapshots != []) [
      "d ${snapshotRoot} 0711 root root -"
      "d ${snapshotRoot}/staging 0711 root root -"
      "d ${snapshotReady} 0700 root root -"
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = builtins.length (builtins.attrNames destinations) <= 4
          && lib.all (name: builtins.match "[a-z][a-z0-9-]{0,31}" name != null) (builtins.attrNames destinations)
          && lib.all (target:
            builtins.match "[A-Za-z0-9][A-Za-z0-9.-]*" target.host != null
            && builtins.match "[a-z_][a-z0-9_-]*" target.user != null
            && builtins.match "/[A-Za-z0-9/_.-]+" target.repository != null
            && !(lib.elem ".." (lib.splitString "/" target.repository))
            && builtins.match "[A-Za-z0-9_-]+" target.sshKeySecret != null
            && builtins.match "[A-Za-z0-9_-]+" target.passphraseSecret != null
            && builtins.match "ssh-ed25519 [A-Za-z0-9+/=]+" target.hostKey != null
            && builtins.hasAttr target.sshKeySecret config.age.secrets
            && builtins.hasAttr target.passphraseSecret config.age.secrets
            && builtins.hasAttr target.sshKeySecret config.hwc.secrets.api
            && builtins.hasAttr target.passphraseSecret config.hwc.secrets.api
            && config.age.secrets.${target.sshKeySecret}.mode == "0440"
            && config.age.secrets.${target.sshKeySecret}.group == "secrets"
            && config.age.secrets.${target.sshKeySecret}.owner == "root"
            && target.sshKeySecret != cfg.repo.remote.sshKeySecret
            && target.passphraseSecret != cfg.encryption.passphraseSecret
          ) (builtins.attrValues destinations)
          && builtins.length (lib.unique (map destinationUrl (builtins.attrValues destinations))) == builtins.length (builtins.attrNames destinations)
          && !(lib.elem repoUrl (map destinationUrl (builtins.attrValues destinations)))
          && builtins.length (lib.unique (map (target: target.passphraseSecret) (builtins.attrValues destinations))) == builtins.length (builtins.attrNames destinations)
          && builtins.length (lib.unique (map (target: target.sshKeySecret) (builtins.attrValues destinations))) == builtins.length (builtins.attrNames destinations)
          && (destinations == {} || cfg.encryption.mode != "none");
        message = "Additional Borg destinations need at most four safe unique SSH paths, pinned ed25519 host keys, declared credentials and independent encrypted identities";
      }
      {
        assertion = builtins.length snapshots <= 16 && lib.all (value:
          builtins.match "[a-z][a-z0-9-]{0,31}" value.name != null
          && lib.hasPrefix "/" value.source
          && !(lib.hasPrefix "${snapshotRoot}/" value.source)
          && builtins.hasAttr value.user config.users.users) snapshots
          && builtins.length (lib.unique (map (value: value.source) snapshots)) == builtins.length snapshots;
        message = "Borg SQLite snapshots need at most 16 unique absolute sources outside staging, safe names and existing application users";
      }
      {
        assertion = cfg.sources != [];
        message = "hwc.data.borg.sources must not be empty";
      }
      {
        assertion = cfg.encryption.mode != "none" || cfg.repo.remote.enable == false;
        message = "Remote Borg repositories must use encryption";
      }
      {
        assertion = !cfg.repo.remote.enable || cfg.repo.remote.path != null;
        message = "hwc.data.borg.repo.remote.enable needs hwc.data.borg.repo.remote.path";
      }
      {
        assertion = cfg.repo.remote.sshKeySecret == null
          || builtins.hasAttr cfg.repo.remote.sshKeySecret config.age.secrets;
        message = "hwc.data.borg.repo.remote.sshKeySecret names an agenix secret that is not declared";
      }
    ];

    warnings = lib.optionals (cfg.encryption.mode == "none") [
      "Borg backup encryption is disabled. This is not recommended for sensitive data."
    ];
  } {
    services.borgbackup.jobs = destinationJobs;
    systemd.services = lib.mkMerge [ (lib.mapAttrs' (name: target:
      lib.nameValuePair "borgbackup-job-${destinationJobName name}"
        (jobService // {
          serviceConfig = jobService.serviceConfig // {
            LoadCredential = [ (destinationCredential target) ];
          };
          onFailure = lib.optionals (cfg.notifications.onFailure && (config.hwc.monitoring.alerts.enable or false))
            [ "hwc-service-failure-notifier@borgbackup-job-${destinationJobName name}.service" ];
        })) destinations)
      (lib.mkIf cfg.monitoring.enable (lib.mapAttrs' (name: target:
        lib.nameValuePair (destinationCheckName name) {
          description = "Check independent Borg repository ${name}";
          restartIfChanged = false;
          onFailure = lib.optionals (cfg.notifications.onFailure && (config.hwc.monitoring.alerts.enable or false))
            [ "hwc-service-failure-notifier@${destinationCheckName name}.service" ];
          environment = {
            BORG_RSH = destinationRsh name target;
            BORG_PASSCOMMAND = "cat ${config.hwc.secrets.api.${target.passphraseSecret}}";
          };
          serviceConfig = jobService.serviceConfig // {
            ExecStart = "${pkgs.borgbackup}/bin/borg check --lock-wait 300 ${destinationUrl target}";
            LoadCredential = [ (destinationCredential target) ];
          };
        }) destinations))
    ];
    systemd.timers = lib.mkMerge [ (lib.mapAttrs' (name: target:
      lib.nameValuePair "borgbackup-job-${destinationJobName name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = { OnCalendar = target.startAt; RandomizedDelaySec = cfg.schedule.randomDelay; Persistent = true; };
      }) destinations)
      (lib.mkIf cfg.monitoring.enable (lib.mapAttrs' (name: target:
        lib.nameValuePair (destinationCheckName name) {
          wantedBy = [ "timers.target" ];
          timerConfig = { OnCalendar = target.checkAt; RandomizedDelaySec = cfg.schedule.randomDelay; Persistent = true; };
        }) destinations))
    ];
    systemd.tmpfiles.rules = lib.optional (destinations != {}) "d ${lockRoot} 0700 root root -";
  } ]);
}
