# ProtonAuthenticator • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.proton-authenticator;
in
{
  # ProtonAuthenticator desktop package
  packages = [ pkgs.proton-authenticator ];

  # User services for auto-start if enabled
  services = lib.mkIf cfg.autoStart {
    proton-authenticator = {
      Unit = {
        Description = "Proton Authenticator 2FA Manager";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.proton-authenticator}/bin/proton-authenticator";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };

  # Environment variables
  env = {
    # Proton Authenticator uses system defaults
  };
}
