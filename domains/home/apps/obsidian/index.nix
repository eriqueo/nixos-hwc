# domains/home/apps/obsidian/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "obsidian";
  description = "Obsidian note-taking app";
  package = pkgs: pkgs.obsidian;
}
