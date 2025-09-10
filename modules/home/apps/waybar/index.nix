# modules/home/apps/waybar/index.nix
{ config, lib, pkgs, ... }:

let
  enabled = config.features.waybar.enable or false;

  flatParts   = ./. + "/parts";
  legacyParts = ../multi/waybar/parts; # only used if you still have the old location
  partsDir =
    if builtins.pathExists (flatParts + "/behavior.nix")
    then flatParts else legacyParts;

  behavior   = import (partsDir + "/behavior.nix")   { inherit lib pkgs; };
  appearance = import (partsDir + "/appearance.nix") { inherit config lib pkgs; };
  packages   = import (partsDir + "/packages.nix")   { inherit lib pkgs; };
  scripts    = import (partsDir + "/scripts.nix")    { inherit lib pkgs; };
in
{
  options.features.waybar.enable = lib.mkEnableOption "Enable Waybar (HM)";

  imports = [
    ../../theme/adapters/waybar-css.nix
    (partsDir + "/scripts.nix")
  ];

  config = lib.mkIf enabled {
    home.packages = packages;

    programs.waybar = {
      enable  = true;
      package = pkgs.waybar;
      settings = behavior;
    };

    xdg.configFile."waybar/style.css".text = appearance;
  };
}
