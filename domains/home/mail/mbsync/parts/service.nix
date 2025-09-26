{ lib, pkgs, haveProton }:
{
  systemd.user.services.mbsync = {
    Unit = {
      Description = "mbsync all";
      After  = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
      Wants  = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.isync}/bin/mbsync -a";
      ExecStartPost = "${pkgs.notmuch}/bin/notmuch new";
      Environment = [
        "PATH=/run/current-system/sw/bin"
        "PASSWORD_STORE_DIR=%h/.password-store"
        "GNUPGHOME=%h/.gnupg"
      ];
    };
  };

  systemd.user.timers.mbsync = {
    Unit.Description = "Periodic mbsync";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      AccuracySec = "30s";
      Persistent = true;
      Unit = "mbsync.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
