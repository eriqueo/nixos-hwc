# NeoMutt • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

{
  # NeoMutt package with extras
  packages = [ pkgs.neomutt ];

  # If you want NeoMutt-specific user services, define them here.
  services = { };

  # Export session env if needed
  env = {
    EDITOR = "nvim"; # Default editor for composing emails
  };
}