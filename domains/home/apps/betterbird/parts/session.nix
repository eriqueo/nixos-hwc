# Betterbird • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

{
  # Betterbird with extras
  packages = [ pkgs.betterbird ];

  # If you want Betterbird-specific user services, define them here.
  # (Most users don't need any; Proton Bridge etc. should be their own module.)
  services = { };

  # Export session env if needed (kept tiny and generic).
  env = {
    BETTERBIRD_PROFILE = "default-release";
  };
}
