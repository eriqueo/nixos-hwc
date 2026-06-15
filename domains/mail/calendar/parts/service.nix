{ lib, pkgs }:
{
  systemd.user.services.vdirsyncer = {
    Unit = {
      Description = "vdirsyncer calendar sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.vdirsyncer}/bin/vdirsyncer sync";
      # gawk is needed by the Radicale pairs' password.fetch (extract one user's
      # line from the multi-user htpasswd by username). coreutils has no awk.
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk ]}"
      ];
      TimeoutStartSec = "120";
      Nice = 10;
    };
  };

  systemd.user.timers.vdirsyncer = {
    Unit.Description = "Periodic vdirsyncer calendar sync";
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      AccuracySec = "1m";
      Persistent = true;
      Unit = "vdirsyncer.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
