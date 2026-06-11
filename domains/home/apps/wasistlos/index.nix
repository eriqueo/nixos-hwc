# domains/home/apps/wasistlos/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "wasistlos";
  description = "WasIstLos WhatsApp client";
  package = pkgs: pkgs.wasistlos;
}
