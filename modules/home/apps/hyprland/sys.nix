# modules/home/apps/hyprland/sys.nix  (HM-only compat: declares options, no system effects)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hyprlandTools;
in
{
  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Hyprland system helpers (compat; no system effects in HM-only mode)";
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Compat flag used by profiles; no system-side behavior in HM-only setup.";
    };
    cursor = {
      theme = lib.mkOption {
        type = lib.types.str;
        default = "Adwaita";
        description = "Declared for compatibility; applied by Home Manager only.";
      };
      size  = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Declared for compatibility; applied by Home Manager only.";
      };
    };
  };

  # HM-only mode: do not set environment variables or packages system-wide.
  # Keep this empty so system layer has zero impact on cursor/env.
  config = lib.mkIf cfg.enable { };
}
