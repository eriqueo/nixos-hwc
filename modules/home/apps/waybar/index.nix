# modules/home/apps/waybar/index.nix
{ lib, pkgs, config, ... }:
let
  # 1) get CSS variables from the adapter
  waybarCss = import ../../theme/adapters/waybar-css.nix { inherit lib pkgs; };

  # 2) call parts as functions
  appearance = import ./parts/appearance.nix { inherit lib; css = waybarCss; };
  behavior   = import ./parts/behavior.nix   { inherit lib; };
  packages   = import ./parts/packages.nix   { inherit lib pkgs; };
  scripts    = import ./parts/scripts.nix    { inherit lib pkgs; };

  cfg = config.features.waybar;
in
{
  options.features.waybar.enable = lib.mkEnableOption "Waybar (HM) configuration";

  config = lib.mkIf cfg.enable {
    # Packages/scripts that belong to HM scope (additions are fine here)
    home.packages = packages;

    programs.waybar = {
      enable = true;
      settings = behavior;      # e.g., JSON-like settings for modules
      style    = appearance;    # CSS string rendered from adapter+appearance
    };

    # If your scripts part returns systemd user services or files:
    # systemd.user.services = scripts.services or {};
    # xdg.configFile."waybar/style.css".text = appearance; # alternative wiring
  };
}

