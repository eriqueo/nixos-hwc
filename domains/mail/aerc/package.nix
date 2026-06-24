# domains/mail/aerc/package.nix
#
# Forked aerc package, consumed from the github:eriqueo/aerc flake input.
# Mirrors the khalt consumption shape in domains/mail/calendar/index.nix
# (`inputs.khalt.packages.${pkgs.system}.default`).
#
# The fork's flake builds via `pkgs.aerc.overrideAttrs { src = self; }` pinned to
# the 0.21.0 tag, so /bin/aerc, libexec/aerc/filters/*, share/aerc/stylesets/*,
# and man pages are produced identically to nixpkgs' aerc. Swap back to
# `pkgs.aerc` for a one-line revert to upstream.
{ pkgs, inputs }:
inputs.aerc.packages.${pkgs.system}.default
