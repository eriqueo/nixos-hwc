{ lib, pkgs, config, ... }:

let
  cfg = config.features.protonBridge or { enable = true; };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.protonmail-bridge ];

    systemd.user.services."protonmail-bridge" = {
      Unit = {
        Description = "ProtonMail Bridge (headless)";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        # First-time auth: run `protonmail-bridge --cli` manually to login.
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive --log-level warn";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "default.target" ]; };
    };
  };
}
