# modules/home/fonts/index.nix
# Font management for user environment

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.fonts;
in {
  imports = [
    ./options.nix
  ];

  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;
    
    home.packages = with pkgs; [
      nerd-fonts.caskaydia-cove
    ];
  };
}