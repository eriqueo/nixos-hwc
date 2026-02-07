{ config, lib, pkgs, osConfig ? {}, ...}:

let
  enabled = config.hwc.home.apps.mpv.enable or false;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    programs.mpv = {
      enable = true;
      config = {
        hwdec = "auto";              # Hardware acceleration
        fullscreen = "yes";          # Default fullscreen for TV
        volume-max = 150;
        osd-level = 1;
      };
      bindings = {
        # Controller-friendly bindings
        UP = "add volume 5";
        DOWN = "add volume -5";
        LEFT = "seek -10";
        RIGHT = "seek 10";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [ ];  # No dependencies
  };
}