{ lib, pkgs, config, ... }:

let
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };

  homeDir = config.home.homeDirectory;
  cfg = config.hwc.home.apps.proton-pass;
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Packages that belong with the app
    home.packages = (session.packages or []);

    # Session variables
    home.sessionVariables = (session.env or {});

    # User services
    systemd.user.services = (session.services or {});

    # File drops (config + helpers)
    home.file = lib.mkMerge [
      (appearance.files homeDir)
      (behavior.files homeDir)
    ];
  };
}
  #==========================================================================
  # VALIDATION
  #==========================================================================