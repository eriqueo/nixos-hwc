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
    #betterbird.enable  = lib.mkEnableOption "bettterbird appearance (HM)";
    #chromium-ui.enable  = lib.mkEnableOption "chromium appearance (HM)";

    # future: betterbird.enable, firefox-ui.enable, chromium-ui.enable, etc.
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
    #==========================================================
    # DYNAMIC IMPORTS - Must be at top level
    #==========================================================
    imports = [
      ./kitty.nix
      ./thunar.nix
      ./waybar/default.nix
      ./hyprland/parts/appearance.nix
    ];

  config = lib.mkIf cfg.enable {
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


  };
}
