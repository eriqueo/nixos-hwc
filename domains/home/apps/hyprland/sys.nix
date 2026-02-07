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

  # Hyprland startup script - system package for launch
  hyprlandStartupScript = pkgs.writeScriptBin "hyprland-startup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # wait for hyprctl to be ready
    TIMEOUT=30; COUNT=0
    until ${pkgs.hyprland}/bin/hyprctl monitors >/dev/null 2>&1; do
      sleep 0.1; COUNT=$((COUNT+1))
      [[ $COUNT -gt $((TIMEOUT*10)) ]] && exit 1
    done

    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 1
    command -v kitty   >/dev/null 2>&1 && kitty   & sleep 0.3 || true
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 2
    command -v firefox >/dev/null 2>&1 && firefox & sleep 0.3 || true
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 3
    command -v thunar  >/dev/null 2>&1 && thunar  & sleep 0.3 || true
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 1
  '';
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
      hwc.system.services.hardware.audio.enable = lib.mkDefault true;
      hwc.system.services.hardware.bluetooth.enable = lib.mkDefault true;

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