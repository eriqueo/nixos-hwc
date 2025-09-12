# modules/home/apps/hyprland/parts/session.nix
{ lib, pkgs, ... }:

let
  hyprlandStartupScript = pkgs.writeScriptBin "hyprland-startup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    log() { echo "[$(date '+%H:%M:%S')] $1" >> /tmp/hypr-startup.log; }
    log "=== Hyprland Startup Begin ==="

    TIMEOUT=30
    COUNTER=0
    until ${pkgs.hyprland}/bin/hyprctl monitors >/dev/null 2>&1; do
      sleep 0.1
      COUNTER=$((COUNTER + 1))
      if [[ $COUNTER -gt $((TIMEOUT * 10)) ]]; then
        log "ERROR: Hyprland not ready after $TIMEOUT seconds"
        exit 1
      fi
    done

    # Optional settle
    sleep 1

    # Workspace 1: terminal
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 1
    command -v kitty   >/dev/null 2>&1 && kitty   & sleep 0.3 || true

    # Workspace 2: browser
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 2
    command -v firefox >/dev/null 2>&1 && firefox & sleep 0.3 || true

    # Workspace 3: file manager
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 3
    command -v thunar  >/dev/null 2>&1 && thunar  & sleep 0.3 || true

    # Return focus
    ${pkgs.hyprland}/bin/hyprctl dispatch workspace 1

    log "=== Hyprland Startup Complete ==="
  '';
in
{
  # Hyprland will run these exactly once at session start.
  # Waybar is launched here so it inherits HM/Hypr env (no user systemd).
  execOnce = [
    "hyprctl setcursor Adwaita 24"
    "hyprland-startup"
    "hyprpaper"
    "waybar"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"
  ];

  # Hyprland's env list ("KEY,VALUE" strings) – used by apps it spawns.
  env = [
    "XCURSOR_THEME,Adwaita"
    "XCURSOR_SIZE,24"
  ];

  # Make the startup script available to the session/user.
  packages = [ hyprlandStartupScript ];
}
