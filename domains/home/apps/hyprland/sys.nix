# modules/home/apps/hyprland/sys.nix - System-side components for Hyprland
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.home.apps.hyprland;

  # Hyprland startup script - moved from home domain for charter compliance
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
    # Provide the startup script as a system package
    environment.systemPackages = [ hyprlandStartupScript ];
  };
}
