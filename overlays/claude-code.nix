# overlays/claude-code.nix
# Backport claude-code from nixpkgs-unstable to stable 24.05
# This overlay takes the unstable nixpkgs input and extracts claude-code

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
