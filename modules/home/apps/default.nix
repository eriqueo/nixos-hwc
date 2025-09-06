# nixos-hwc/modules/home/apps/default.nix
#
# HOME APPS AGGREGATOR (v6) - UI-only app configs behind toggles.
# No environment.systemPackages or systemd.services here.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps = {
    enable = lib.mkEnableOption "Enable Home-layer app configs";

    kitty.enable     = lib.mkEnableOption "Kitty terminal (HM)";
    thunar.enable    = lib.mkEnableOption "Thunar (HM)";
    waybar.enable    = lib.mkEnableOption "Waybar UI (HM)";
    hyprland.enable  = lib.mkEnableOption "Hyprland appearance (HM)";
    # future: betterbird.enable, firefox-ui.enable, chromium-ui.enable, etc.
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    imports =
      (lib.optionals cfg.kitty.enable    [ ../apps/kitty.nix ]) ++
      (lib.optionals cfg.thunar.enable   [ ../apps/thunar.nix ]) ++
      (lib.optionals cfg.waybar.enable   [ ../apps/waybar/default.nix ]) ++
      (lib.optionals cfg.hyprland.enable [ ../apps/hyprland/parts/appearance.nix ]);
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  assertions = [
    {
      assertion = !(config ? environment && config.environment ? systemPackages)
               && !(config ? systemd && config.systemd ? services);
      message   = "Home apps aggregator must not set system packages/services.";
    }
  ];
}
