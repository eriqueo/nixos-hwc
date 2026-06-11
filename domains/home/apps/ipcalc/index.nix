# domains/home/apps/ipcalc/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "ipcalc";
  description = "ipcalc IP calculator";
  package = pkgs: pkgs.ipcalc;
}
