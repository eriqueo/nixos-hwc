{
  lib,
  pkgs,
  haveProton,
  afewPkg,
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
  coreArgs = lib.concatMapStringsSep " " lib.escapeShellArg coreChannels;
  transportArgs = lib.concatMapStringsSep " " lib.escapeShellArg transportChannels;
  trashArgs = lib.concatMapStringsSep " " lib.escapeShellArg trashChannels;
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
    TimeoutStartSec = "1h";
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
      set -uo pipefail

      export NOTMUCH_CONFIG="$HOME/.notmuch-config"
      NM=${pkgs.notmuch}/bin/notmuch
      MAILDIR=${lib.escapeShellArg maildirRoot}
      STATUS_FILE=${lib.escapeShellArg statusFile}
      STATUS_DIR="$(${pkgs.coreutils}/bin/dirname "$STATUS_FILE")"
      LOCK_FILE="$STATUS_DIR/sync.lock"
      CONFIG_DIGEST=${lib.escapeShellArg configDigest}
      BRIDGE_VERSION=${lib.escapeShellArg bridgeVersion}
      CORE_CHANNELS=( ${coreArgs} )
      TRANSPORT_CHANNELS=( ${transportArgs} )
      TRASH_CHANNELS=( ${trashArgs} )

      mode="''${1:-core}"
      case "$mode" in core|trash|all) ;; *)
        printf 'usage: sync-mail [core|trash|all]\n' >&2
        exit 2
      esac

      ${pkgs.coreutils}/bin/mkdir -p "$STATUS_DIR"
      if [[ ''${SYNC_MAIL_LOCKED:-0} != 1 ]]; then
        exec ${pkgs.util-linux}/bin/flock -n -E 75 "$LOCK_FILE" \
          ${pkgs.coreutils}/bin/env SYNC_MAIL_LOCKED=1 "$0" "$@"
      fi

      ensure_status() {
        if ! ${pkgs.jq}/bin/jq -e '.schemaVersion == 1 and (.lanes | type == "object")' \
            "$STATUS_FILE" >/dev/null 2>&1; then
          local tmp
          tmp=$(${pkgs.coreutils}/bin/mktemp "$STATUS_DIR/.status.XXXXXX")
          ${pkgs.jq}/bin/jq -n \
            '{schemaVersion:1,retention:"AUTO-MANAGED bounded one file",lanes:{}}' > "$tmp"
          ${pkgs.coreutils}/bin/chmod 600 "$tmp"
          ${pkgs.coreutils}/bin/mv -f "$tmp" "$STATUS_FILE"
        fi
      }

      state_digest() {
        local lane=$1
        if [[ "$lane" == trash ]]; then
          if [[ -f "$MAILDIR/proton/Trash/.mbsyncstate" ]]; then
            ${pkgs.coreutils}/bin/sha256sum "$MAILDIR/proton/Trash/.mbsyncstate"
          else
            printf 'missing-trash-state\n'
          fi
        else
          ${pkgs.findutils}/bin/find "$MAILDIR" -type f -name .mbsyncstate \
            ! -path "$MAILDIR/proton/Trash/*" -print0 2>/dev/null \
            | ${pkgs.coreutils}/bin/sort -z \
            | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.coreutils}/bin/sha256sum
        fi | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.gawk}/bin/awk '{print $1}'
      }

      record_lane() {
        local lane=$1 state=$2 outcome=$3 exit_code=$4 at epoch digest case_id previous tmp
        at=$(${pkgs.coreutils}/bin/date -Iseconds)
        epoch=$(${pkgs.coreutils}/bin/date +%s)
        digest=$(state_digest "$lane")
        case_id=$(printf '%s\0%s\0%s\0%s\0%s' \
          "$lane" "$CONFIG_DIGEST" "$BRIDGE_VERSION" "$digest" "$outcome" \
          | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.gawk}/bin/awk '{print $1}')
        previous=$(${pkgs.jq}/bin/jq -r --arg lane "$lane" '.lanes[$lane].state // "unknown"' "$STATUS_FILE")
        tmp=$(${pkgs.coreutils}/bin/mktemp "$STATUS_DIR/.status.XXXXXX")
        ${pkgs.jq}/bin/jq \
          --arg lane "$lane" --arg state "$state" --arg outcome "$outcome" \
          --arg caseId "$case_id" --arg at "$at" --argjson epoch "$epoch" \
          --argjson exitCode "$exit_code" '
            .lanes[$lane] = {
              caseId: $caseId,
              state: $state,
              lastOutcome: $outcome,
              exitCode: $exitCode,
              lastAttempt: $at,
              lastAttemptEpoch: $epoch,
              lastSuccess: (if $state == "healthy" then $at else (.lanes[$lane].lastSuccess // null) end),
              lastSuccessEpoch: (if $state == "healthy" then $epoch else (.lanes[$lane].lastSuccessEpoch // null) end)
            }
          ' "$STATUS_FILE" > "$tmp"
        ${pkgs.coreutils}/bin/chmod 600 "$tmp"
        ${pkgs.coreutils}/bin/mv -f "$tmp" "$STATUS_FILE"
        if [[ "$previous" != "$state" ]]; then
          printf 'mail-sync transition lane=%s state=%s->%s outcome=%s case=%s\n' \
            "$lane" "$previous" "$state" "$outcome" "$case_id"
        fi
      }

      declare -A lane_rc=()
      declare -a selected=()
      afew_rc=0
      run_lane() {
        local lane=$1
        shift
        selected+=("$lane")
        if ${pkgs.isync}/bin/mbsync "$@"; then
          lane_rc[$lane]=0
        else
          lane_rc[$lane]=$?
          printf 'mbsync lane %s failed with code %s; indexing continues\n' \
            "$lane" "''${lane_rc[$lane]}" >&2
        fi
      }

      prefetch_index_rc=0
      transport_rc=0
      residency_rc=0
      run_core() {
        # Fetch folder membership before interpreting local intent. Do not pull
        # flags here: the normal two-way pass reconciles phone AND local stars.
        run_lane core --pull-new --pull-gone --create-near --remove-near --expunge-near "''${CORE_CHANNELS[@]}"
        if [[ ''${#TRASH_CHANNELS[@]} -gt 0 ]]; then
          run_lane trash "''${TRASH_CHANNELS[@]}"
        fi
        "$NM" new || prefetch_index_rc=$?
        if [[ ''${lane_rc[core]} -ne 0 || ''${lane_rc[trash]:-0} -ne 0 || "$prefetch_index_rc" -ne 0 ]]; then
          return
        fi
        ${lib.optionalString (residencyCommand != "") ''
        ${residencyCommand} || residency_rc=$?
        ''}
        ${lib.optionalString (transportCommand != "") ''
        # Flush pending local stars while source copies still exist. Reservations
        # record reconciled flags; Proton Trash can then clear its Starred label.
        run_lane core --pull-flags --push-flags "''${TRANSPORT_CHANNELS[@]}"
        if [[ ''${lane_rc[core]} -ne 0 ]]; then
          return
        fi
        ${transportCommand} --phase apply || transport_rc=$?
        ''}
        if [[ "$transport_rc" -ne 0 ]]; then
          return
        fi
        ${lib.optionalString (transportCommand != "") ''
        # Transport can associate existing messages with remote Trash. Fetch
        # that result before a stale local Inbox can reach the mover or push.
        run_lane core --pull-new --pull-gone --create-near --remove-near --expunge-near "''${TRANSPORT_CHANNELS[@]}"
        if [[ ''${#TRASH_CHANNELS[@]} -gt 0 ]]; then
          run_lane trash "''${TRASH_CHANNELS[@]}"
        fi
        "$NM" new || prefetch_index_rc=$?
        if [[ ''${lane_rc[core]} -ne 0 || ''${lane_rc[trash]:-0} -ne 0 || "$prefetch_index_rc" -ne 0 ]]; then
          return
        fi
        ''}
        # Only durable intent markers can drive this mover. Plain folder tags
        # are observations and cannot authorize an upload.
        ${afewPkg}/bin/afew -m -a || afew_rc=$?
        if [[ "$afew_rc" -ne 0 ]]; then
          return
        fi
        run_lane core "''${CORE_CHANNELS[@]}"
        ${lib.optionalString (transportCommand != "") ''
        if [[ ''${lane_rc[core]} -eq 0 ]]; then
          ${transportCommand} --phase ack || transport_rc=$?
        fi
        ''}
      }

      ensure_status
      case "$mode" in
        core|all) run_core ;;
        trash) run_lane trash "''${TRASH_CHANNELS[@]}" ;;
      esac

      index_rc=0
      "$NM" new || index_rc=$?
      final_rc=$index_rc
      [[ "$prefetch_index_rc" -eq 0 ]] || final_rc=$prefetch_index_rc
      for lane in "''${selected[@]}"; do
        rc=''${lane_rc[$lane]}
        if [[ "$index_rc" -ne 0 ]]; then
          record_lane "$lane" degraded index-failed "$index_rc"
        elif [[ "$rc" -ne 0 ]]; then
          record_lane "$lane" degraded sync-failed "$rc"
          [[ "$final_rc" -ne 0 ]] || final_rc=$rc
        elif [[ "$lane" == core && ( "$prefetch_index_rc" -ne 0 || "$transport_rc" -ne 0 || ''${lane_rc[trash]:-0} -ne 0 ) ]]; then
          reconciliation_rc=$transport_rc
          [[ "$prefetch_index_rc" -eq 0 ]] || reconciliation_rc=$prefetch_index_rc
          [[ ''${lane_rc[trash]:-0} -eq 0 ]] || reconciliation_rc=''${lane_rc[trash]}
          record_lane "$lane" degraded reconciliation-failed "$reconciliation_rc"
          [[ "$final_rc" -ne 0 ]] || final_rc=$reconciliation_rc
        elif [[ "$lane" == core && "$afew_rc" -ne 0 ]]; then
          record_lane "$lane" degraded mover-failed "$afew_rc"
          [[ "$final_rc" -ne 0 ]] || final_rc=$afew_rc
        else
          record_lane "$lane" healthy success 0
        fi
      done

      ${lib.optionalString (residencyCommand != "") ''
      if [[ "$mode" != trash ]]; then
        if [[ "$final_rc" -eq 0 ]]; then
          if [[ "$residency_rc" -eq 0 ]]; then
            record_lane residency healthy shadow-success 0
          else
            record_lane residency degraded observation-failed "$residency_rc"
            final_rc=$residency_rc
          fi
        else
          record_lane residency degraded prerequisite-failed "$final_rc"
        fi
      fi
      ''}

      ${pkgs.coreutils}/bin/rm -f "''${XDG_CACHE_HOME:-$HOME/.cache}/mbsync-last-success"
      ${lib.optionalString (projectionCommand != "") ''
      if [[ "$mode" != trash ]]; then
        if [[ "$final_rc" -eq 0 ]]; then
          labels_rc=0
          ${projectionCommand} || labels_rc=$?
          if [[ "$labels_rc" -eq 0 ]]; then
            record_lane labels healthy projection-success 0
          else
            record_lane labels degraded projection-failed "$labels_rc"
            final_rc=$labels_rc
          fi
        else
          record_lane labels degraded prerequisite-failed "$final_rc"
        fi
      fi
      ''}
      exit "$final_rc"
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
