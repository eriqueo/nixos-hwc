# Plasma

## Purpose
Provide a familiar stock KDE desktop without replacing later user choices.

## Boundaries
Owns user defaults, browser/file associations and the desktop help file.
System login, power authority, graphics and Steam runtime have separate owners.

## Structure
`index.nix` owns `hwc.home.apps.plasma.enable`, packages and seed-only defaults.
User configuration is CRITICAL personal state; activation only creates absent
defaults. Installed packages are replaceable from the committed configuration.

## Changelog
- 2026-10-25: Add stock Breeze defaults, double-click navigation, Firefox/Dolphin
  associations and AC no-suspend settings for an isolated household desktop.
