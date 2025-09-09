# modules/home/apps/hyprland/index.nix
{ lib, pkgs, config, ... }:
let
  # 1) get themed tokens for Hyprland
  hyprTheme = import ../../theme/adapters/hyprland.nix { inherit lib pkgs; };

  # 2) call parts as *functions*, not imports
  appearance = import ./parts/appearance.nix { inherit lib pkgs; theme = hyprTheme; };
  behavior   = import ./parts/behavior.nix   { inherit lib; };
  hardware   = if builtins.pathExists ./parts/hardware.nix
               then import ./parts/hardware.nix { inherit lib; }
               else {};
  session    = import ./parts/session.nix    { inherit lib; };

  cfg = config.features.hyprland;
in
{
  # 3) options live in features.* (keep compat aliases if you’re mid-migration)
  options.features.hyprland.enable = lib.mkEnableOption "Hyprland (HM) configuration";

  # 4) write merged settings into the actual HM option
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = lib.mkMerge [ appearance behavior hardware session ];
    };
  };
}
