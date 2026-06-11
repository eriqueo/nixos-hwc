# domains/home/apps/bottles-unwrapped/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "bottles-unwrapped";
  description = "Bottles Wine manager (unwrapped)";
  package = pkgs: pkgs.bottles-unwrapped;
}
