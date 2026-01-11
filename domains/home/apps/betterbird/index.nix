{ lib, pkgs, config, osConfig ? {}, ...}:

let
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };
  tools      = import ./parts/tools.nix      { inherit lib pkgs config; };
  profile    = import ./parts/profile.nix    { inherit lib pkgs config; };

  homeDir     = config.home.homeDirectory;
  profileBase = "${homeDir}/.betterbird";
  cfg = config.hwc.home.apps.betterbird;
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Packages: session + tools + profile
    {
      home.packages = (session.packages or []) ++ (tools.packages or []) ++ (profile.packages or []);
    }

    # Session variables
    {
      home.sessionVariables = (session.env or {}) // (profile.env or {});
    }

    # User services: tools + session + profile
    {
      systemd.user.services = (tools.services or {}) // (session.services or {}) // (profile.services or {});
    }

    # File drops (theming + prefs + profile)
    {
      home.file = lib.mkMerge [
        (appearance.files profileBase)
        (behavior.files   profileBase)
        (profile.files profileBase)
      ];
    }

    # Home activation scripts from profile
    (lib.mkIf (profile ? activation) {
      home.activation = profile.activation;
    })
  ]);
}

  #==========================================================================
  # VALIDATION
  #==========================================================================