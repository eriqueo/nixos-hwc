# overlays/cloudflared.nix
# Backport cloudflared from nixpkgs-unstable to stable 25.11.
# nixos-25.11 ships cloudflared 2025.11.1; unstable tracks upstream
# (2026.5.0 at time of writing). Cloudflared is a Go static binary so
# crossing the stable/unstable boundary is low-risk.

{ nixpkgs-unstable }:

final: prev:
let
  pkgs-unstable = import nixpkgs-unstable {
    system = prev.system;
    config.allowUnfree = true;
  };
in {
  cloudflared = pkgs-unstable.cloudflared;
}
