# overlays/cloudflared.nix
# Backport cloudflared from nixpkgs-unstable to stable 26.05.
# At the 26.05 migration, stable has 2026.5.2 and locked unstable has
# 2026.7.3. Cloudflared is a Go static binary so
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
