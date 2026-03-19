{ lib, pkgs, haveProton, afewPkg, osConfig ? {}}:
{
  home.file.".local/bin/sync-mail" = {
    text = ''
#!/usr/bin/env bash
set -euo pipefail
export NOTMUCH_CONFIG="$HOME/.notmuch-config"

echo "$(date): Starting mail sync..."

# Move tagged messages to correct IMAP folders BEFORE mbsync
${afewPkg}/bin/afew -m -a || true

# Sync all accounts
${pkgs.isync}/bin/mbsync -a

# Index new mail (triggers post-new hook for tagging)
${pkgs.notmuch}/bin/notmuch new

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