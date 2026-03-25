# domains/home/apps/hyprland/sys.nix
# System-lane dependencies for Hyprland window manager
#
# ARCHITECTURE NOTE:
# This sys.nix file belongs to the SYSTEM lane, co-located with the home module.
# It defines its own system-lane options (hwc.system.apps.hyprland.*) because:
# 1. System lane evaluates BEFORE Home Manager
# 2. Cannot depend on hwc.home.apps.hyprland.enable (doesn't exist yet)
# 3. Must be independently controlled from machine config
# 4. Validation assertions ensure consistency between system and home lanes

{ lib, config, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.system.apps.hyprland;

  # Import helper scripts from parts/
  hyprlandScripts = import ./parts/scripts.nix { inherit pkgs lib; };

  # Hyprland startup script - imported from parts/ (pure derivation)
  hyprlandStartupScript = import ./parts/startup.nix { inherit pkgs; };
in
{
  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.hyprland = {
    enable = lib.mkEnableOption "Hyprland system dependencies (startup script, helper scripts)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [
    # Conditional implementation when enabled
    (lib.mkIf cfg.enable {
      #========================================================================
      # DEPENDENCY FORCING (System domain)
      #========================================================================
      # Hyprland requires these system services
      hwc.system.hardware.audio.enable = lib.mkDefault true;
      hwc.system.hardware.bluetooth.enable = lib.mkDefault true;

      #========================================================================
      # SYSTEM PACKAGES
      #========================================================================
      # Provide the startup script and helper scripts as system packages
      environment.systemPackages = [ hyprlandStartupScript ] ++ hyprlandScripts;
    })

    # Note: Cross-lane validation happens in the home module (index.nix)
    # The home module can check if system-lane is enabled (system evaluates first)
    # But system cannot check home-lane (Home Manager evaluates later)
    {}
  ];
}