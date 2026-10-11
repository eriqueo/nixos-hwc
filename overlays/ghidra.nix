# overlays/ghidra.nix
# Backport ghidra from nixpkgs-unstable to stable 26.05.
#
# REA (domains/home/apps/rea) accepts only Ghidra 12.1.x and refuses 12.0.4
# with `unsupported_version` at analysis time (checked 2026-10-11, rea-agents
# 6.3.0). Stable 26.05 carries 12.0.4; the locked unstable carries 12.1.2,
# which cache.nixos.org serves. Ghidra is a self-contained Java tree with its
# own JDK on PATH, so crossing the stable/unstable boundary is low-risk.
#
# TEMPORARY (tracked, Charter §0.2). Remove when nixpkgs-stable's ghidra is
# 12.1 or newer: `nix eval .#nixosConfigurations.hwc-home.pkgs.ghidra.version`
# without this overlay reports >= 12.1. parts/package.nix asserts the range,
# so a stale overlay fails the build rather than REA at runtime.

{ nixpkgs-unstable }:

final: prev:
let
  pkgs-unstable = import nixpkgs-unstable {
    system = prev.system;
    config.allowUnfree = true;
  };
in {
  ghidra = pkgs-unstable.ghidra;
}
