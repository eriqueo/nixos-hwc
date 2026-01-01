# ProtonMail • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.proton-mail;
in
{
  # ProtonMail desktop package
  packages = [ pkgs.protonmail-desktop ];

  # User services for auto-start if enabled
  services = lib.mkIf cfg.autoStart {
    protonmail = {
      Unit = {
        Description = "ProtonMail Desktop Client";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.protonmail-desktop}/bin/protonmail-desktop --hidden";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };

  # Environment variables
  env = {
    # ProtonMail uses system defaults
  };
}