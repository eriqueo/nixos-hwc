# ProtonMail • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.proton-mail;
  # Own the plain command because Hyprland autostarts `proton-mail` directly.
  # A desktop-entry-only wrapper leaves that real caller outside the boundary.
  launcher = pkgs.writeShellScriptBin "proton-mail" ''
    if command -v gpu-integrated >/dev/null 2>&1; then
      exec gpu-integrated ${pkgs.protonmail-desktop}/bin/proton-mail "$@"
    fi
    exec ${pkgs.protonmail-desktop}/bin/proton-mail "$@"
  '';
in
{
  # Keep the package's icons/data while resolving its colliding executable to
  # the command-level integrated-GPU boundary above.
  packages = [ (lib.hiPrio launcher) pkgs.protonmail-desktop ];

  # Override the package's desktop file so ordinary launcher use reaches the
  # same integrated-GPU boundary as the optional autostart service.
  desktopEntries.proton-mail = {
    name = "Proton Mail";
    comment = "Proton official desktop application for Proton Mail and Proton Calendar";
    genericName = "Proton Mail";
    exec = "${lib.getExe launcher} %U";
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
        ExecStart = "${lib.getExe launcher} --hidden";
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
