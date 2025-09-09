# WAYBAR - Wayland status bar configuration (Charter v6 Final)
# This module orchestrates the Waybar parts and is enabled via the
# hwc.home.apps.waybar.enable toggle, following the 5-File Pattern.

# modules/home/apps/waybar/index.nix
# Same behavior as your old default.nix; only the entrypoint name changes.
{ config, lib, pkgs, ... }:

let
  # Existing toggle you’re already using
  cfg = config.hwc.home.apps.waybar;

  # During the transition, parts might be flat (final) or under multi/ (legacy)
  flatParts   = ./. + "/parts";
  legacyParts = ../multi/waybar/parts;
  partsDir =
    if builtins.pathExists (flatParts + "/behavior.nix")
    then flatParts
    else legacyParts;

  # Import parts exactly like your default.nix did
  behavior  = import (partsDir + "/behavior.nix")  { inherit lib pkgs; };
  appearance = import (partsDir + "/appearance.nix") { inherit config lib pkgs; };
  packages  = import (partsDir + "/packages.nix")  { inherit lib pkgs; };
in
{
  # Keep the same imports your default.nix had
  imports = [
    ../../theme/adapters/waybar-css.nix
    (partsDir + "/scripts.nix")
  ];

  # Gate everything behind the existing enable flag
  config = lib.mkIf cfg.enable {
    home.packages = packages;

    programs.waybar = {
      enable  = true;
      package = pkgs.waybar;
      settings = behavior;
    };

    # Write CSS produced by appearance part
    xdg.configFile."waybar/style.css".text = appearance;
  };
}
