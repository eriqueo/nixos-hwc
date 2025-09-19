{ lib, pkgs, config, ... }:

let
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };
  theme     = import ./parts/theme.nix     { inherit config lib; };


  homeDir = config.home.homeDirectory;
  cfg = config.features.neomutt;
in
{
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable { 
    home.packages = (session.packages or []); # Packages that belong with the app
    home.sessionVariables = (session.env or {}); # Session variables
    systemd.user.services = (session.services or {});    # User services


    # File drops (theming + config)
    home.file = lib.mkMerge [
      (appearance.files config.home.homeDirectory)
      (behavior.files   config.home.homeDirectory)
    ];
  };
}
