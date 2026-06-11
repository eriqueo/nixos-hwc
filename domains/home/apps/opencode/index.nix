# domains/home/apps/opencode/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "opencode";
  description = "OpenCode";
  package = pkgs: pkgs.opencode;
}
