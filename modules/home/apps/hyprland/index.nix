# HM entrypoint for Hyprland — imports parts only in Home Manager scope.
{ lib, ... }:
let
  importIfExists = path: if builtins.pathExists path then [ path ] else [];
in {
  imports =
    # Prefer flat layout (final)
    (importIfExists ./parts/appearance.nix)
    ++ (importIfExists ./parts/behavior.nix)
    ++ (importIfExists ./parts/hardware.nix)
    ++ (importIfExists ./parts/session.nix)

    # Fallback to old multi/ layout during transition
    ++ (importIfExists ../multi/hyprland/parts/appearance.nix)
    ++ (importIfExists ../multi/hyprland/parts/behavior.nix)
    ++ (importIfExists ../multi/hyprland/parts/hardware.nix)
    ++ (importIfExists ../multi/hyprland/parts/session.nix);
}
