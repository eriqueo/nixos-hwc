# domains/home/apps/google-cloud-sdk/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "google-cloud-sdk";
  description = "Google Cloud SDK";
  package = pkgs: pkgs.google-cloud-sdk;
}
