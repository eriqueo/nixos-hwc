{
  lib,
  pkgs,
  haveProton,
  source,
  accountChannels,
  coreChannels,
  transportChannels,
  trashChannels,
  maildirRoot,
  statusFile,
  configDigest,
  bridgeVersion,
  trashTimerEnable,
  residencyCommand,
  projectionCommand,
  transportCommand,
  ...
}:
let
  fetchFlags = [ "--pull-new" "--pull-gone" "--create-near" "--remove-near" "--expunge-near" ];
  sync = args: [ "${pkgs.isync}/bin/mbsync" ] ++ args;
  shell = command: lib.optionals (command != "") [ "${pkgs.bash}/bin/bash" "-c" command ];
  coordinatorConfig = pkgs.writeText "mail-coordinator.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit configDigest bridgeVersion;
    ledger = if transportCommand != "" then "/var/lib/hwc/mail-classifier/ledger.sqlite" else null;
    accounts = lib.mapAttrs (name: channels: {
      fetch = sync (fetchFlags ++ channels ++ lib.optionals (name == "proton") trashChannels);
      trash = if name == "proton" then sync trashChannels else [];
      upload = sync (if name == "proton" then [ "${name}-drafts" "${name}-sent" ] else channels);
    }) accountChannels;
    index = [ "${pkgs.notmuch}/bin/notmuch" "new" ];
    observation = shell residencyCommand;
    labels = shell projectionCommand;
    labelReport = "${builtins.dirOf statusFile}/labels.json";
    # One physical membership owner; mbsync mirrors verified provider effects.
    commandSteps = lib.optionals (transportCommand != "") [
      [ "flags" (sync ([ "--pull-flags" "--push-flags" ] ++ transportChannels)) ]
      [ "apply" (shell "${transportCommand} --phase apply") ]
      [ "mirror" (sync (fetchFlags ++ transportChannels ++ trashChannels)) ]
      [ "index" [ "${pkgs.notmuch}/bin/notmuch" "new" ] ]
    ] ++ lib.optionals (transportCommand != "") [
      [ "ack" (shell "${transportCommand} --phase ack") ]
    ] ++ [ [ "final-index" [ "${pkgs.notmuch}/bin/notmuch" "new" ] ] ];
  });
  unitDeps = {
    After = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
    Wants = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
  };
  serviceDefaults = {
    Type = "oneshot";
    SuccessExitStatus = [ 75 ];
    Environment = [
      "PATH=${pkgs.notmuch}/bin:/run/current-system/sw/bin"
      "PASSWORD_STORE_DIR=%h/.password-store"
      "GNUPGHOME=%h/.gnupg"
      "NOTMUCH_CONFIG=%h/.notmuch-config"
    ];
    TimeoutStartSec = "15m";
    TimeoutStopSec = "15s";
    Nice = 10;
    CPUQuota = "50%";
    IOSchedulingClass = "best-effort";
    IOSchedulingPriority = 6;
  };
in
{
  home.file.".local/bin/sync-mail" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      export NOTMUCH_CONFIG="$HOME/.notmuch-config"
      exec ${pkgs.python3}/bin/python3 ${source}/scripts/mail_classifier.py coordinate \
        --config ${coordinatorConfig} --status ${lib.escapeShellArg statusFile} \
        --mode "''${1:-core}" "''${@:2}"
    '';
  };

  home.activation.removeLegacyMbsyncMarker = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/rm -f "''${XDG_CACHE_HOME:-$HOME/.cache}/mbsync-last-success"
  '';

  systemd.user.services.mbsync = {
    Unit = unitDeps // {
      Description = "Synchronize core mailboxes";
      ConditionPathExists = "%h/.mbsyncrc";
    };
    Service = serviceDefaults // {
      ExecStart = "%h/.local/bin/sync-mail core";
    };
  };

  systemd.user.timers.mbsync = {
    Unit.Description = "Periodic core mailbox synchronization";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      AccuracySec = "30s";
      Persistent = true;
      Unit = "mbsync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.mbsync-trash = {
    Unit = unitDeps // {
      Description = "Synchronize isolated Proton Trash mailbox";
      ConditionPathExists = "%h/.mbsyncrc";
    };
    Service = serviceDefaults // {
      ExecStart = "%h/.local/bin/sync-mail trash";
    };
  };

  systemd.user.timers.mbsync-trash = {
    Unit.Description = "Daily isolated Proton Trash synchronization";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
      Unit = "mbsync-trash.service";
    };
    Install.WantedBy = lib.optionals trashTimerEnable [ "timers.target" ];
  };
}
