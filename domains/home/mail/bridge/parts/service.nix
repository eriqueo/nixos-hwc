{ lib, pkgs, br, runtime }:
{
  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "ProtonMail Bridge (headless)";
      After = [ "default.target" "network-online.target" "graphical-session.target" "gpg-agent.service" ];
      Wants = [ "network-online.target" "gpg-agent.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${(br.package or pkgs.protonmail-bridge)}/bin/protonmail-bridge ${runtime.args}";
      Restart = "on-failure";
      RestartSec = "${toString (br.restartSec or 5)}";
      Environment = runtime.env ++ [ "GPG_TTY=%t/tty" ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };
}
