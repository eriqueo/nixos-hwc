# overlays/claude-code.nix
# Backport claude-code from an unstable nixpkgs into the stable package sets.
# Stable 26.05 freezes claude-code at the version it branched with (2.1.223 as
# of 2026-10-25) while the CLI ships several releases a week.
#
# Fed the `nixpkgs` (nixos-unstable) input, so claude-code on the stable
# machines is only as fresh as the last `nix flake update nixpkgs`. A dedicated
# input decoupling the two was tried on 2026-10-25 and removed the same day:
# nixos-unstable's HEAD was the rev the pin already named, and Law 14 forbids
# two inputs that resolve identically. Reintroduce the separate input only when
# the channel is genuinely behind on this package again.

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
