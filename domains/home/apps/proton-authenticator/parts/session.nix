# ProtonAuthenticator • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.proton-authenticator;
in
{
  # ProtonAuthenticator desktop package
  packages = [ pkgs.proton-authenticator ];

  # User services (unused for autostart; autostart handled via XDG entry)
  services = { };

  # XDG autostart entry to launch hidden into the system tray (Waybar tray)
  autostartFiles = lib.mkIf cfg.autoStart {
    "autostart/proton-authenticator.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Proton Authenticator
      Comment=Proton Authenticator auto-start
      Exec=${pkgs.proton-authenticator}/bin/proton-authenticator --hidden
      Icon=proton-authenticator
      Terminal=false
      X-GNOME-Autostart-enabled=true
    '';
  };

  # Environment variables
  env = {
    # Proton Authenticator uses system defaults
  };
}
