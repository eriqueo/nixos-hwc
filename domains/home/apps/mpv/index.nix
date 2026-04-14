# domains/home/apps/mpv/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.mpv;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.mpv = {
    enable = lib.mkEnableOption "mpv media player";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
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