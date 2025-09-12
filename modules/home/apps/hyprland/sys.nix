# modules/home/apps/hyprland/sys.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hyprlandTools;
in
{
  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Hyprland system helpers (cursor, env, packages)";
    cursor = {
      theme = lib.mkOption { type = lib.types.str; default = "Adwaita"; };
      size  = lib.mkOption { type = lib.types.int; default = 24; };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure cursor theme assets exist system-wide
    environment.systemPackages = [ pkgs.adwaita-icon-theme ];

    # Export cursor env to all login / graphical sessions
    environment.sessionVariables = {
      XCURSOR_THEME = cfg.cursor.theme;
      XCURSOR_SIZE  = toString cfg.cursor.size;
      # Useful in odd environments to help resolution:
      XCURSOR_PATH  = "${pkgs.adwaita-icon-theme}/share/icons";
    };

    # Also export to user services (Waybar, etc.)
    systemd.user.sessionVariables = {
      XCURSOR_THEME = cfg.cursor.theme;
      XCURSOR_SIZE  = toString cfg.cursor.size;
      XCURSOR_PATH  = "${pkgs.adwaita-icon-theme}/share/icons";
    };
  };
}
