# modules/home/apps/waybar/index.nix
{ config, lib, pkgs, ... }:
let
  cfg       = config.features.waybar;
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs; };
  appearance= import ./parts/appearance.nix { inherit config lib pkgs; };
  packages  = import ./parts/packages.nix  { inherit lib pkgs; };
  scripts   = import ./parts/scripts.nix   { inherit pkgs lib; };  # <— NEW: list of bins
in
{
  options.features.waybar.enable =
    lib.mkEnableOption "Enable Waybar";

  # remove: imports = [ ./parts/scripts.nix ... ];
  imports = [ ../../theme/adapters/waybar-css.nix ];

  config = lib.mkIf cfg.enable {
    # Include both regular packages and the generated script bins
    home.packages = packages ++ scripts;

    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = behavior;
    };

    xdg.configFile."waybar/style.css".text = appearance;
  };
}
