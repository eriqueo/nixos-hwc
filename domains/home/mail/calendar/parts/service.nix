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
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.coreutils ]}"
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
