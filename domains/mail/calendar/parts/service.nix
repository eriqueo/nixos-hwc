{ lib, pkgs, dataDir }:
let
  # vdirsyncer refuses to sync until `discover` has recorded each pair's
  # collections — on a new host, and again after any change to its config
  # (e.g. a Radicale collection added to a pair). Discover whenever the
  # config differs from the one last discovered (hash kept beside status/),
  # answering yes to creating missing collections; unchanged config never
  # re-discovers, so a collection deleted on one side stays deleted.
  firstDiscover = pkgs.writeShellScript "vdirsyncer-discover-on-change" ''
    set -eu
    data="${dataDir}"
    data="''${data/#\~/$HOME}"
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/vdirsyncer/config"
    stamp="$data/discovered-config.sha256"
    want=$(sha256sum "$conf" | cut -d' ' -f1)
    if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$want" ]; then
      yes | ${pkgs.vdirsyncer}/bin/vdirsyncer discover
      mkdir -p "$data" && printf '%s\n' "$want" > "$stamp"
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
