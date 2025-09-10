# modules/home/apps/hyprland/index.nix
{ config, lib, pkgs, ... }:

let
  # Allow either old or new toggle namespace during migration
  # new (preferred):
  newToggle = config.features.hyprland.enable or null;
  # old (legacy):
  oldToggle = config.hwc.home.apps.hyprland.enable or null;
  enabled =
    if newToggle != null then newToggle
    else if oldToggle != null then oldToggle
    else false;

  # Theme adapter + parts (parts are *functions*, not modules)
  hyprTheme  = import ../../theme/adapters/hyprland.nix { inherit lib pkgs; };
  behavior   = import ./parts/behavior.nix   { inherit lib;        };
  hardware   = if builtins.pathExists ./parts/hardware.nix
               then import ./parts/hardware.nix { inherit lib pkgs; } else {};
  session    = import ./parts/session.nix    { inherit lib pkgs;   };
  appearance = import ./parts/appearance.nix { inherit lib pkgs; theme = hyprTheme; };

  wallpaperPath = ../../theme/nord-mountains.jpg;
in
{
  # expose the *new* option; you can keep/remove this once profiles all use it
  options.features.hyprland.enable = lib.mkEnableOption "Hyprland (HM) configuration";

  # optional: alias old → new so both work during refactor
  imports = [
    (lib.mkAliasOptionModule
      [ "hwc" "home" "apps" "hyprland" "enable" ]
      [ "features" "hyprland" "enable" ])
  ];

  config = lib.mkIf enabled {
    home.packages = with pkgs; [
      wofi hyprshot hypridle hyprpaper hyprlock cliphist wl-clipboard
      brightnessctl networkmanager wirelesstools hyprsome
    ] ++ (session.packages or []);

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;
      settings = lib.mkMerge [
        {
          monitor   = hardware.monitor or null;
          workspace = hardware.workspace or null;
          input     = hardware.input or null;
        }
        (behavior // { "$mod" = "SUPER"; })
        { exec-once = session.execOnce or []; }
        appearance
      ];
    };

    home.file.".config/hypr/hyprpaper.conf".text = ''
      preload = ${wallpaperPath}
      wallpaper = eDP-1,${wallpaperPath}
      wallpaper = DP-1,${wallpaperPath}
      splash = false
    '';
  };
}
