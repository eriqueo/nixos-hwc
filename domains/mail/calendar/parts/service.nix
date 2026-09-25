{ lib, pkgs, dataDir }:
let
  # First run on a host: vdirsyncer refuses to sync until `discover` has
  # recorded each pair's collections under status/. Run it once, answering
  # yes to creating the missing local collections; later runs skip it so a
  # collection deleted on one side is never silently re-created.
  firstDiscover = pkgs.writeShellScript "vdirsyncer-first-discover" ''
    status="${dataDir}/status"
    status="''${status/#\~/$HOME}"
    if [ ! -d "$status" ] || [ -z "$(ls -A "$status")" ]; then
      yes | ${pkgs.vdirsyncer}/bin/vdirsyncer discover
    fi
  '';
in
{
  systemd.user.services.vdirsyncer = {
    Unit = {
      Description = "vdirsyncer calendar sync";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${firstDiscover}";
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
