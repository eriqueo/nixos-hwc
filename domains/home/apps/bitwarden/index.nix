# One-package desktop client; account data stays in Bitwarden's own state.
import ../../../lib/mkSimpleApp.nix {
  name = "bitwarden";
  description = "Bitwarden desktop client for the self-hosted vault";
  package = pkgs: pkgs.bitwarden-desktop;
}
