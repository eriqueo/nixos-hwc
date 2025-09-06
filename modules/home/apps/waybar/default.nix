# WAYBAR - Wayland status bar configuration (Charter v6 Final)
# This module orchestrates the Waybar parts and is enabled via the
# hwc.home.apps.waybar.enable toggle, following the 5-File Pattern.

{ config, lib, pkgs, ... }:

let
  # Define a shorthand for this module's options.
  cfg = config.hwc.home.apps.waybar;

  # Import all the parts here in the top-level `let` block.
  # This makes them available throughout the rest of the file.
  behavior = import ./parts/behavior.nix { inherit lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit config lib pkgs; };
  packages = import ./parts/packages.nix { inherit lib pkgs; };
in
{
  # 1. Unconditionally import the theme adapter module.
  # This makes the `hwc.home.theme.adapters.waybar.css` option available
  # to other modules, like our `appearance.nix` part.
  imports = [ ../../theme/adapters/waybar-css.nix ];

  # 2. The `config` block contains all the settings.
  # We wrap the entire block in `lib.mkIf` to make this whole module
  # controllable by the single `hwc.home.apps.waybar.enable` toggle.
  config = lib.mkIf cfg.enable {

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
# Write the CSS "appearance" part to the correct XDG config file path.
    # We use builtins.trace to print the value of 'appearance' to the console during the build.
    xdg.configFile."waybar/style.css".text = builtins.trace appearance;
  };
}
