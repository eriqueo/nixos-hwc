# Modern Terminal Games

## Purpose
Install MTG with Breaker, Paddle Battle, Snek and Alien Raid.
Run `mtg` for the menu or `mtg breaker` to start Breaker directly.

## Boundaries
Owns Nix packaging and installation. Game behavior stays in the upstream source input.
Enabled only on the laptop. Tetro remains a separate application.

## Structure
- `index.nix`: enable/package options, locked Rust dependencies, ALSA support, workspace tests and installation.
- `flake.lock` pins the `mtg` source input. Run `nix flake update mtg` to update it.

## Changelog
- 2026-11-12: Replace Atari-style and its input patches with MTG; remove the laptop's nSnake, nInvaders and Curse of War selections and retain Tetro.
