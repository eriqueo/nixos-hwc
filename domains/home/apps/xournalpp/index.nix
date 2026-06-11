# domains/home/apps/xournalpp/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "xournalpp";
  description = "xournalpp PDF annotator and note-taker";
  package = pkgs: pkgs.xournalpp;
}
