# modules/home/apps/dunst/index.nix
{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.home.apps.dunst.enable or false;
  
  # Import appearance configuration
  appearance = import ./parts/appearance.nix { inherit config lib pkgs; };
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
    # Install dunst package
    home.packages = with pkgs; [ dunst ];
    
    # Configure dunst service
    services.dunst = {
      enable = true;
      settings = appearance.settings;
    };
  };
}
  #==========================================================================
  # VALIDATION
  #==========================================================================