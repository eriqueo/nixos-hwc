# domains/home/apps/imv/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "imv";
  description = "imv image viewer";
  package = pkgs: pkgs.imv;
}
