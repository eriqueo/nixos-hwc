# modules/home/fonts/index.nix
# Font management for user environment

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.theme.fonts;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.theme.fonts = {
    enable = lib.mkEnableOption "Enable HWC font management for user environment";
  };

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
