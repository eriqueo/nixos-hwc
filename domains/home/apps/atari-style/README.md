# Atari-style

## Purpose
Install the upstream terminal arcade collection. Run `atari-style` to choose a game.

## Boundaries
Owns Nix packaging and installation. Game behavior stays in the upstream flake input, with a terminal-input lifecycle patch until upstream keeps cbreak active for the full session.
The public entry point owns terminal input mode for menu-launched games.
Enabled only on the laptop. No services or automatic game launches.

## Structure
- `index.nix`: enable/package options, Python dependencies, upstream checks and installation.
- `terminal-session.patch`: session-wide input mode, compatible X/Y controller selection, manual Breakout launch, one keyboard read per game frame, game-loop movement/action tests, and a real-terminal regression test for menu/game input, normal exit and SIGTERM.
- Source comes from the `atari-style` input in `flake.lock`.

## Changelog
- 2026-11-12: Skip one-axis keyboard system-control devices on startup and reconnect when choosing a joystick; scan for a compatible X/Y controller. Remove Breakout timed auto-launch and test idle behavior and device selection.
- 2026-11-11: Route each keyboard event once through Breakout, Galaga and Grand Prix; test paddle/ship/car movement, ball launch, firing and acceleration in both upstream game namespaces.
- 2026-11-11: Keep key echo disabled between reads and restore terminal settings on exit; test through the public entry point with cursor and character-set escape sequences decoded and bounded capture and output draining during exit.
- 2026-11-11: Add the terminal arcade package with metadata and shader assets, upstream registry/game/input checks, pygame community edition metadata, and laptop opt-in.
