# Atari-style

## Purpose
Install the upstream terminal arcade collection. Run `atari-style` to choose a game.

## Boundaries
Owns Nix packaging and installation. Game behavior stays in the upstream flake input.
Enabled only on the laptop. No services or automatic game launches.

## Structure
- `index.nix`: enable/package options, Python dependencies, upstream checks and installation.
- Source comes from the `atari-style` input in `flake.lock`.

## Changelog
- 2026-11-11: Add the terminal arcade package with metadata and shader assets, upstream registry/game/input checks, pygame community edition metadata, and laptop opt-in.
