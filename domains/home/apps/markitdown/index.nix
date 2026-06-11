# domains/home/apps/markitdown/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "markitdown";
  description = "markitdown — convert PDF/DOCX/XLSX/images/audio to Markdown";
  package = pkgs: pkgs.python3Packages.markitdown;
}
