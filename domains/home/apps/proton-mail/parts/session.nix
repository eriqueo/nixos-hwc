# ProtonMail • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.proton-mail;
  launcher = pkgs.writeShellScript "protonmail-integrated" ''
    if command -v gpu-integrated >/dev/null 2>&1; then
      exec gpu-integrated ${pkgs.protonmail-desktop}/bin/proton-mail "$@"
    fi
    exec ${pkgs.protonmail-desktop}/bin/proton-mail "$@"
  '';
in
{
  # ProtonMail desktop package
  packages = [ pkgs.protonmail-desktop ];

  # Override the package's desktop file so ordinary launcher use reaches the
  # same integrated-GPU boundary as the optional autostart service.
  desktopEntries.proton-mail = {
    name = "Proton Mail";
    comment = "Proton official desktop application for Proton Mail and Proton Calendar";
    genericName = "Proton Mail";
    exec = "${launcher} %U";
    icon = "proton-mail";
    terminal = false;
    categories = [ "Network" "Email" ];
    mimeType = [ "x-scheme-handler/mailto" ];
    startupNotify = true;
  };

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
