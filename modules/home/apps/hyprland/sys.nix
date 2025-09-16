# modules/home/apps/hyprland/sys.nix  (HM-only compat: declares options, no system effects)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hyprlandTools;
in
{
  # HM-only mode: do not set environment variables or packages system-wide.
  # Keep this empty so system layer has zero impact on cursor/env.
  config = lib.mkIf cfg.enable { };
}
