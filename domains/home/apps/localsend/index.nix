# domains/home/apps/localsend/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "localsend";
  description = "LocalSend file sharing";
  package = pkgs: pkgs.localsend;
}
