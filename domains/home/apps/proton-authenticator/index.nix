{ config, lib, pkgs, osConfig ? {}, ...}:

let
  cfg = config.hwc.home.apps.proton-authenticator;
  session = import ./parts/session.nix { inherit lib pkgs config; };
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

    # XDG config files (autostart entries, etc.)
    xdg.configFile = (session.autostartFiles or {});
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
