# ProtonAuthenticator • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.proton-authenticator;
in
{
  # ProtonAuthenticator desktop package
  packages = [ pkgs.proton-authenticator ];

  # User services (unused - autostart handled via Hyprland exec-once)
  services = { };

  # XDG autostart removed - exec-once in Hyprland handles boot-only startup
  autostartFiles = { };

  # Environment variables
  env = {
    # Proton Authenticator uses system defaults
  };
}
