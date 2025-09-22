{ lib, pkgs, config, ... }:

let
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };
  tools      = import ./parts/tools.nix      { inherit lib pkgs config; };

  homeDir     = config.home.homeDirectory;
  profileBase = "${homeDir}/.thunderbird";
  cfg = config.hwc.home.apps.betterbird;
in
{
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable {
    # Packages that belong with the app (you can add betterbird here if you package it)
    home.packages = (session.packages or []) ++ (tools.packages or []);

    # Session variables (none are strictly required, but session/env is supported)
    home.sessionVariables = (session.env or {});

    # User services: tools + session
    systemd.user.services = (tools.services or {}) // (session.services or {});

    # File drops (theming + prefs)
    home.file = lib.mkMerge [
      (appearance.files profileBase)
      (behavior.files   profileBase)
    ];
  };
}
