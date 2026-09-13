# ProtonMail • Session part
# Session-scoped things only: packages, user services, env.
{
  lib,
  pkgs,
  config,
  osConfig ? { },
  ...
}:

let
  cfg = config.hwc.home.apps.proton-mail;
  launcher = pkgs.writeShellScript "protonmail-integrated" ''
    if command -v gpu-integrated >/dev/null 2>&1; then
      exec gpu-integrated ${pkgs.protonmail-desktop}/bin/protonmail-desktop "$@"
    fi
    exec ${pkgs.protonmail-desktop}/bin/protonmail-desktop "$@"
  '';
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
        ExecStart = "${launcher} --hidden";
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
