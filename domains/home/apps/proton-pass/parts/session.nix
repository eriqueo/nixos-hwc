# ProtonPass • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.protonPass;
in
{
  # ProtonPass desktop package
  packages = [ pkgs.proton-pass ];

  # User services for auto-start if enabled
  services = lib.mkIf cfg.autoStart {
    proton-pass = {
      Unit = {
        Description = "ProtonPass Password Manager";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.proton-pass}/bin/proton-pass --hidden";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };

  # Environment variables
  env = {
    # ProtonPass uses system defaults
  };
}