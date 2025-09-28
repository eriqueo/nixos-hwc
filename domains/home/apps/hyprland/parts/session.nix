# modules/home/apps/hyprland/parts/session.nix
{ config, lib, pkgs, ... }:

let
  cur = config.hwc.home.theme.cursor or {};
  xc  = cur.xcursor or {};
  hc  = cur.hyprcursor or {};
  cursorSize = toString (cur.size or 24);

  pkgByName = name:
    if lib.hasAttr name pkgs then builtins.getAttr name pkgs else pkgs.adwaita-icon-theme;
  xcPkg = pkgByName (xc.package or "adwaita-icon-theme");

  xcursorName    = xc.name or "Adwaita";
  hyprcursorName = hc.name or xcursorName;

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

  hyprcursorSource =
    if (hc ? assetPathRel) then ../../.. + "/${hc.assetPathRel}" else null;

in
{
  # FLAT KEYS (NO nested `settings = {}`!)
  execOnce = [
    "xfconfd"

    "hyprctl setcursor ${hyprcursorName} ${cursorSize}"
    "hyprland-startup"
    "hyprpaper"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"
  ];

  env = [
    "HYPRCURSOR_THEME,${hyprcursorName}"
    "HYPRCURSOR_SIZE,${cursorSize}"
    "XCURSOR_THEME,${xcursorName}"
    "XCURSOR_SIZE,${cursorSize}"
    "XCURSOR_PATH,${xcPkg}/share/icons"
  ];

  packages = [ hyprlandStartupScript ];

  files = lib.mkIf (hyprcursorSource != null) {
    ".local/share/icons/${hyprcursorName}".source = hyprcursorSource;
  };
}
