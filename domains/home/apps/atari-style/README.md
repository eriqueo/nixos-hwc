# Atari-style

## Purpose
Install the upstream terminal arcade collection. Run `atari-style` to choose a game.

## Boundaries
Owns Nix packaging and installation. Game behavior stays in the upstream flake input, with a terminal-input lifecycle patch until upstream keeps cbreak active for the full session.
Enabled only on the laptop. No services or automatic game launches.

## Structure
- `index.nix`: enable/package options, Python dependencies, upstream checks and installation.
- `terminal-session.patch`: session-wide input mode and a real-terminal regression test for menu/game input, normal exit and SIGTERM.
- Source comes from the `atari-style` input in `flake.lock`.

## Changelog
- 2026-11-11: Keep key echo disabled between reads and restore terminal settings on exit; test through the public entry point with cursor and character-set escape sequences decoded and bounded capture.
- 2026-11-11: Add the terminal arcade package with metadata and shader assets, upstream registry/game/input checks, pygame community edition metadata, and laptop opt-in.
