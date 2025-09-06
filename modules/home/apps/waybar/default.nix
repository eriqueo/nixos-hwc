# WAYBAR - Wayland status bar configuration (Charter v6 Refactor)
# This module orchestrates the Waybar parts and is enabled via the
# hwc.home.apps.waybar.enable toggle, following the 5-File Pattern.

{ config, lib, pkgs, ... }:

let
  # This module reads its OWN enable flag from the options
  # defined in modules/home/apps/default.nix
  cfg = config.hwc.home.apps.waybar;
in
# The entire output of this file is wrapped in a lib.mkIf, making it
# controllable by the toggle in your main configuration.
lib.mkIf cfg.enable {

  # Let block to import the standardized parts, keeping the main config clean.
  let
    # How Waybar acts (module layout, on-click actions, exec commands)
    behavior = import ./parts/behavior.nix { inherit lib pkgs; };

    # How Waybar looks (CSS theming)
    appearance = import ./parts/appearance.nix { inherit lib pkgs; };

    # What Waybar needs (package dependencies)
    packages = import ./parts/packages.nix { inherit lib pkgs; };
  in
  {
    # Assign the packages part to home.packages.
    # This ensures Waybar and all its tools are in the correct PATH.
    home.packages = packages;

    # Configure the main Waybar program.
    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      # The settings are Waybar's "behavior"
      settings = behavior;
    };

    # Write the CSS "appearance" part to the correct XDG config file path.
    xdg.configFile."waybar/style.css".text = appearance;
  }
}
