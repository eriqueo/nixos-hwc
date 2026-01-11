# modules/home/apps/hyprland/parts/session.nix
{ config, lib, pkgs, osConfig ? {}, ... }:

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

  # Startup script removed from home domain for charter compliance
  # Script is now provided by co-located sys.nix as system package

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

  packages = [ ]; # hyprland-startup script now provided by system packages

  files = lib.mkIf (hyprcursorSource != null) {
    ".local/share/icons/${hyprcursorName}".source = hyprcursorSource;
  };
}