# ProtonPass • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.proton-pass;
in
{
  # ProtonPass desktop package
  packages = [ pkgs.proton-pass ];

  # User services removed - autostart handled via Hyprland exec-once
  # This ensures boot-only startup without restart on rebuilds
  services = { };

  # Environment variables
  env = {
    # ProtonPass uses system defaults
  };
}