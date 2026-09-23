# domains/home/apps/eden/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "eden";
  description = "Switch 1 emulator derived from Yuzu and Sudachi";
  package = pkgs: pkgs.eden;
}
