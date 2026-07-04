# overlays/rclone.nix
# Backport rclone from nixpkgs-unstable to stable 25.11.
# nixos-25.11 ships rclone 1.72.1, whose `iclouddrive` backend cannot
# authenticate against Apple's current endpoints (fails with HTTP 400
# "Invalid Session Token" before the 2FA prompt). Fixed in rclone 1.74.0 via
# proper SRP authentication (rclone/rclone#9209 + #9234, merged 2026-04-27);
# unstable currently tracks 1.74.1. rclone is a Go static binary so crossing
# the stable/unstable boundary is low-risk.
# REMOVE WHEN: locked `nixpkgs-stable` ships rclone >= 1.74.0
# (check: nix eval .#nixosConfigurations.hwc-server.pkgs.rclone.version).

{ nixpkgs-unstable }:

final: prev:
let
  pkgs-unstable = import nixpkgs-unstable {
    system = prev.system;
    config.allowUnfree = true;
  };
in {
  rclone = pkgs-unstable.rclone;
}
