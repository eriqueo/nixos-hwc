# HM entrypoint for Waybar — imports parts only in Home Manager scope.
{ lib, ... }:
let
  importIfExists = path: if builtins.pathExists path then [ path ] else [];
in {
  imports =
    # Prefer flat layout (final)
    (importIfExists ./parts/appearance.nix)
    ++ (importIfExists ./parts/behavior.nix)
    ++ (importIfExists ./parts/packages.nix)
    ++ (importIfExists ./parts/scripts.nix)

    # Fallback to old multi/ layout during transition
    ++ (importIfExists ../multi/waybar/parts/appearance.nix)
    ++ (importIfExists ../multi/waybar/parts/behavior.nix)
    ++ (importIfExists ../multi/waybar/parts/packages.nix)
    ++ (importIfExists ../multi/waybar/parts/scripts.nix);
}
