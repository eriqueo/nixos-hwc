{ lib, pkgs, haveProton, afewPkg, osConfig ? {}}:
{
  home.file.".local/bin/sync-mail" = {
    text = ''
#!/usr/bin/env bash
set -euo pipefail
export NOTMUCH_CONFIG="$HOME/.notmuch-config"
NM="${pkgs.notmuch}/bin/notmuch"
LABELS_DIR="$HOME/400_mail/Maildir/proton/Labels"

echo "$(date): Starting mail sync..."

# Move tagged messages to correct IMAP folders BEFORE mbsync
${afewPkg}/bin/afew -m -a || true

# --- Label copy-back: DISABLED 2026-04-05 ---
# Proton Bridge rejects IMAP APPEND for messages that already exist under a
# different label, causing every sync to fail with "far side refuses to store".
# Notmuch tagging still works locally; labels just won't push back to Proton.
# TODO: investigate Bridge IMAP COPY or Proton API for proper label sync.

# Sync all accounts (tolerate partial failures so notmuch new always runs)
_sync_rc=0
${pkgs.isync}/bin/mbsync -a || _sync_rc=$?
if [ "$_sync_rc" -ne 0 ]; then
  echo "Warning: mbsync exited with code $_sync_rc (continuing to index)"
fi

# Index new mail (triggers post-new hook for tagging)
"$NM" new

# Mark successful sync for health monitoring (even when no new mail)
${pkgs.coreutils}/bin/touch "''${XDG_CACHE_HOME:-$HOME/.cache}/mbsync-last-success"

if [ "$_sync_rc" -ne 0 ]; then
  echo "$(date): Mail sync completed with warnings (mbsync rc=$_sync_rc)"
  exit "$_sync_rc"
else
  echo "$(date): Mail sync completed"
fi
    '';
    executable = true;
  };
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
      ];

      # sync-mail handles: afew move-mails → mbsync → notmuch new
      ExecStart =
        "${pkgs.util-linux}/bin/flock -n %h/.cache/mbsync.lock -c '%h/.local/bin/sync-mail'";

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