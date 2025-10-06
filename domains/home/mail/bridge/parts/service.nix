{ lib, pkgs, br, runtime }:
{
  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "ProtonMail Bridge (headless)";
      After = [ "default.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${(br.package or pkgs.protonmail-bridge)}/bin/protonmail-bridge ${runtime.args}";
      Restart = "on-failure";
      RestartSec = "${toString (br.restartSec or 5)}";
      Environment = runtime.env;
    };
    Install = { WantedBy = [ "default.target" ]; };
  };
}
