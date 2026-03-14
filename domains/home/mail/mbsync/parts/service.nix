{ lib, pkgs, haveProton, afewPkg, maildirRoot, osConfig ? {}}:

let
  # Pre-sync script: physically moves Maildir files based on notmuch tags
  # so mbsync can push the moves back to Proton.
  # Runs: afew --move-mails (archive/trash/spam) + label copy-back
  preSyncScript = pkgs.writeShellScript "mail-presync" ''
    set -euo pipefail
    export NOTMUCH_CONFIG="$HOME/.notmuch-config"
    export PATH=${lib.makeBinPath [ pkgs.notmuch pkgs.coreutils pkgs.findutils ]}

    # ── 1. System folder moves (archive / trash / spam) ──────────────────────
    # afew MailMover reads [MailMover] from ~/.config/afew/config and
    # physically moves files before mbsync pushes them to Proton.
    ${afewPkg}/bin/afew --move-mails || true

    # ── 2. Label copy-back (aerc tag → Proton label) ─────────────────────────
    # For each label folder that exists in Proton (proton/Labels/<label>/),
    # hard-link any notmuch-tagged messages into that folder so mbsync can
    # push the label assignment to Proton. Falls back to cp if hard-link fails.
    LABELS_DIR="${maildirRoot}/proton/Labels"
    [ -d "$LABELS_DIR" ] || exit 0

    for label_dir in "$LABELS_DIR"/*/; do
      [ -d "$label_dir" ] || continue
      label=$(basename "$label_dir")
      # Skip Bridge's underscore-prefixed internal mirror folders
      case "$label" in _*) continue ;; esac

      mkdir -p "$label_dir/cur" "$label_dir/new" "$label_dir/tmp"

      ${pkgs.notmuch}/bin/notmuch search --output=files "tag:$label" 2>/dev/null \
        | while IFS= read -r src; do
          [ -f "$src" ] || continue
          fname=$(basename "$src")
          base_id="''${fname%%:2,*}"

          # Skip if a file with this base ID already exists in the label dir
          existing=$(find "$label_dir/cur" "$label_dir/new" \
            -name "''${base_id}:*" -o -name "''${base_id}" 2>/dev/null | head -1)
          [ -n "$existing" ] && continue

          ln "$src" "$label_dir/cur/$fname" 2>/dev/null \
            || cp "$src" "$label_dir/cur/$fname" 2>/dev/null \
            || true
        done
    done
  '';
in
{
  systemd.user.services.mbsync = {
    Unit = {
      Description = "mbsync all";
      ConditionPathExists = "%h/.mbsyncrc";
      After  = [ "network-online.target" ]
               ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
      Wants  = [ "network-online.target" ]
               ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
    };
    Service = {
      Type = "oneshot";

      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p %h/.cache"
        # Run pre-sync moves so mbsync pushes them to Proton
        "${preSyncScript}"
      ];

      ExecStart =
        "${pkgs.util-linux}/bin/flock -n %h/.cache/mbsync.lock -c '%h/.local/bin/sync-mail'";

      # Ensure hooks can find notmuch; never fail the unit on hook errors
      ExecStartPost =
        "${pkgs.bash}/bin/bash -lc '${pkgs.notmuch}/bin/notmuch new || true'";

      Environment = [
        # include notmuch in PATH for any child processes (hooks)
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
  };

  systemd.user.timers.mbsync = {
    Unit.Description = "Periodic mbsync";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      AccuracySec = "30s";
      Persistent = true;
      Unit = "mbsync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}