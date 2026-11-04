# overlays/claude-code.nix
# Backport the existing unstable channel's Claude CLI to stable hosts.
# TEMPORARY: stable 26.05 has 2.1.223, below T3's 2.1.293 minimum.
# Remove when the stable channel satisfies the minimum required by T3.
# The laptop uses its native installation, selected by the home app module.

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
