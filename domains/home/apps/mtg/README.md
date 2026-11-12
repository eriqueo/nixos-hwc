# Modern Terminal Games

## Purpose
Install the owned MTG fork with Frogger, Breaker, Paddle Battle, Snek and Alien Raid.
Run `mtg` for the menu or `mtg frogger` for the crossing game.
Frogger: arrows/WASD hop, Space starts, P pauses, R restarts, Q quits.
It needs a 70x30 terminal; shrinking pauses play until P resumes it.

## Boundaries
Owns Nix packaging and installation. Game behavior and tests stay in the owned `eriqueo/mtg` source input.
Enabled only on the laptop. Tetro remains a separate application.

## Structure
- `index.nix`: enable/package options, locked Rust dependencies, ALSA support, workspace tests and installation.
- `flake.lock` pins the private `mtg` source through GitHub SSH. Updating it requires repository access.
- The source workspace owns deterministic Frogger tests; `crates/frogger/verify.py` exercises a real PTY outside the Nix sandbox.
- SBC hardware and controller support remain unverified.

## Changelog
- 2026-11-12: Add Frogger from the owned MTG fork; preserve the four upstream games and Tetro.
- 2026-11-12: Replace Atari-style and its input patches with MTG; remove the laptop's nSnake, nInvaders and Curse of War selections and retain Tetro.
