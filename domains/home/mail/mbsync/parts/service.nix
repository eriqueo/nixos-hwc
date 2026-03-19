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

# --- Label copy-back: sync notmuch label tags → Labels/ Maildir ---
# For each known Labels/ folder, ensure Maildir file presence matches tag state.
# Hard-links add the label on Proton (via mbsync APPEND); deletions remove it
# (via mbsync Expunge Both). Only iterates folders that already exist in Proton.
if [ -d "$LABELS_DIR" ]; then
  for _ldir in "$LABELS_DIR"/*/; do
    [ -d "$_ldir" ] || continue
    _lname=$(basename "$_ldir")
    case "$_lname" in _*) continue ;; esac  # skip Bridge internal mirrors
    mkdir -p "$_ldir/new" "$_ldir/cur"

    # ADD: messages with tag:$_lname that have no file in Labels/$_lname/
    while IFS= read -r _src; do
      [ -f "$_src" ] || continue
      case "$_src" in */Labels/*) continue ;; esac  # don't link from another Label copy
      _fname=$(basename "$_src")
      if [ ! -e "$_ldir/cur/$_fname" ] && [ ! -e "$_ldir/new/$_fname" ]; then
        ln "$_src" "$_ldir/new/$_fname" 2>/dev/null || true
      fi
    done < <("$NM" search --output=files \
        "tag:$_lname AND NOT path:proton/Labels/$_lname/**" 2>/dev/null || true)

    # REMOVE: files in Labels/$_lname/ whose message no longer has tag:$_lname
    while IFS= read -r _mid; do
      "$NM" search --output=files "$_mid" 2>/dev/null \
        | grep "Labels/$_lname" \
        | xargs -r rm -f
    done < <("$NM" search --output=messages \
        "path:proton/Labels/$_lname/** AND NOT tag:$_lname" 2>/dev/null || true)
  done
fi

# Sync all accounts
${pkgs.isync}/bin/mbsync -a

# Index new mail (triggers post-new hook for tagging)
"$NM" new

echo "$(date): Mail sync completed"
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