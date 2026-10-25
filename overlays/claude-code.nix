# overlays/claude-code.nix
# Single fleet-wide source for claude-code, overriding BOTH nixpkgs channels.
# Neither channel tracks the CLI: stable 26.05 freezes at the version it
# branched with (2.1.223 as of 2026-10-25), and the `nixpkgs` pin is only as
# fresh as the last world rebuild (2.1.220), while the CLI ships several
# releases a week. Wired into mkPkgs' base overlay list, so stable and
# unstable machines alike resolve the same build.
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
