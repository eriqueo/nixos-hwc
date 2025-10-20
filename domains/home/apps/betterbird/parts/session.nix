# Betterbird • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

{
  # Thunderbird (betterbird removed from nixpkgs)
  packages = [ pkgs.thunderbird ];

  # If you want Betterbird-specific user services, define them here.
  # (Most users don't need any; Proton Bridge etc. should be their own module.)
  services = { };

  # Export session env if needed (kept tiny and generic).
  env = {
    THUNDERBIRD_PROFILE = "default-release";
  };
}
