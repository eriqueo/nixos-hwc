# domains/home/apps/hyprland/sys.nix
# System-side dependencies for Hyprland window manager
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.home.apps.hyprland;

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
  config = lib.mkIf cfg.enable {
    #==========================================================================
    # DEPENDENCY FORCING (System domain)
    #==========================================================================
    # Hyprland requires these system services
    hwc.system.services.hardware.audio.enable = lib.mkDefault true;
    hwc.system.services.hardware.bluetooth.enable = lib.mkDefault true;

    #==========================================================================
    # IMPLEMENTATION
    #==========================================================================
    # Provide the startup script and helper scripts as system packages
    environment.systemPackages = [ hyprlandStartupScript ] ++ hyprlandScripts;

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.enable;
        message = "hwc.home.apps.hyprland.enable must be true for system dependencies to be active";
      }
    ];
  };
}