# modules/home/apps/hyprland/index.nix
{ config, lib, pkgs, ... }:

let
  enabled = config.features.hyprland.enable or false;

  # Parts (all imported the same way)
  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs; };
  hardware   = if builtins.pathExists ./parts/hardware.nix
               then import ./parts/hardware.nix { inherit lib pkgs; } else {};
  session    = import ./parts/session.nix    { inherit config lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs; theme = theme.settings or theme; };

  # Normalize each part to a uniform shape
  asPart = p: {
    settings = p.settings or p;          # allow old parts that returned settings directly
    packages = p.packages or [];
    files    = p.files    or {};
  };

  parts = map asPart [ theme behavior hardware session appearance ];

  # Collect packages and files from all parts
  partPkgs  = lib.flatten (map (p: p.packages) parts);
  partFiles = lib.foldl' (acc: p: acc // p.files) {} parts;

  # Base packages for Hyprland app domain
  basePkgs = with pkgs; [
    wofi hyprshot hypridle hyprpaper hyprlock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome
  ];

  # Merge settings from parts (order matters: base -> behavior -> session/env -> appearance)
  mergedSettings = lib.mkMerge (map (p: p.settings) parts);

in
{
  options.features.hyprland.enable = lib.mkEnableOption "Enable Hyprland (HM)";

  config = lib.mkIf enabled {
    home.packages = basePkgs ++ partPkgs;
    home.file     = partFiles;

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;
      settings = mergedSettings;
    };

  };
}
