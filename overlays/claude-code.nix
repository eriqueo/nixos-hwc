# overlays/claude-code.nix
# Backport claude-code from an unstable nixpkgs into the stable package sets.
# Stable 26.05 freezes claude-code at the version it branched with (2.1.223 as
# of 2026-10-25) while the CLI ships several releases a week.
#
# `nixpkgs-unstable` is the ROLE, not a specific input: flake.nix feeds this the
# dedicated `nixpkgs-claude-code` pin so the CLI's version is independent of a
# whole-machine channel bump. Bump: change that input's rev in flake.nix.

{ nixpkgs-unstable }:

final: prev:
let
  # Import nixpkgs-unstable with allowUnfree for claude-code
  pkgs-unstable = import nixpkgs-unstable {
    system = prev.system;
    config = {
      allowUnfree = true;
    };
  };
in {
  # Import claude-code from nixpkgs-unstable
  claude-code = pkgs-unstable.claude-code;
}
