# nixos-hwc/modules/home/hyprland/default.nix
#
# Home UI: Hyprland Wayland Compositor (Universal Config Domains)
# Charter v5 compliant - Single entrypoint composing universal behavior/hardware/session/appearance domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#   - modules/home/theme/palettes/deep-nord.nix (theme tokens)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#   Universal domains: behavior.nix, hardware.nix, session.nix, appearance.nix
#

# modules/home/apps/hyprland/index.nix
# Same behavior as your old default.nix; only the entrypoint name changes.
{ config, lib, pkgs, ... }:

let
  # Keep the same enable flag you already use today.
  cfg = config.hwc.home.apps.hyprland;

  # While migrating, parts might be in the flat folder *or* under multi/.
  flatParts = ./. + "/parts";
  legacyParts = ../multi/hyprland/parts;
  partsDir =
    if builtins.pathExists (flatParts + "/behavior.nix")
    then flatParts
    else legacyParts;

  behavior = import (partsDir + "/behavior.nix") { inherit lib pkgs; };
  hardware = import (partsDir + "/hardware.nix") { inherit lib pkgs; };
  session  = import (partsDir + "/session.nix")  { inherit lib pkgs; };

  # Same theme adapter path you used before:
  themeSettings = config.hwc.home.theme.adapters.hyprland.settings;
  appearance    = import (partsDir + "/appearance.nix") { inherit lib pkgs; theme = themeSettings; };

  # Same wallpaper path as before (relative to this file’s location)
  wallpaperPath = ../../theme/nord-mountains.jpg;
in
lib.mkIf cfg.enable {

  home.packages = with pkgs; [
    wofi hyprshot hypridle hyprpaper hyprlock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome
  ] ++ session.packages;

  home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    settings = lib.mkMerge [
      {
        monitor   = hardware.monitor;
        workspace = hardware.workspace;
        input     = hardware.input;
      }
      (behavior // { "$mod" = "SUPER"; })
      { exec-once = session.execOnce; }
      appearance
    ];
  };

  home.file.".config/hypr/hyprpaper.conf".text = ''
    preload = ${wallpaperPath}
    wallpaper = eDP-1,${wallpaperPath}
    wallpaper = DP-1,${wallpaperPath}
    splash = false
  '';
}

