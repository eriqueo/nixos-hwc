# modules/home/fonts/index.nix
# Font management for user environment

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.theme.fonts;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;
    
    home.packages = with pkgs; [
      nerd-fonts.caskaydia-cove
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}