# nixos-hwc/modules/home/hyprland/parts/input.nix
#
# Hyprland Input Configuration: Touchpad and Keyboard Settings
# Charter v4 compliant - Pure data for input device behavior
#
# DEPENDENCIES (Upstream):
#   - None (hardware input configuration)
#
# USED BY (Downstream):
#   - modules/home/hyprland/default.nix
#
# USAGE:
#   let inp = import ./parts/input.nix { inherit lib pkgs; };
#   in { input = inp.input; }
#

{ lib, pkgs, ... }:
{
  input = {
    kb_layout = "us";
    follow_mouse = 1;
    touchpad = {
      natural_scroll = true;
    };
  };
}