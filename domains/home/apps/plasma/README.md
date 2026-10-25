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
The one exception is the lid policy: `plasmaLidPolicy` rewrites PowerDevil's
`LidAction` for every power profile on each activation, because the host also
runs household services and PowerDevil's session-wide handle-lid-switch
inhibitor makes `services.logind` unable to decide lid behavior.

## Changelog
- 2026-10-25: Enforce `LidAction=0` for the AC, Battery and LowBattery profiles
  so a closed lid never suspends the host; the seed kept only AC and could not
  reach an already-written `powerdevilrc`.
- 2026-10-25: Add stock Breeze defaults, double-click navigation, Firefox/Dolphin
  associations and AC no-suspend settings for an isolated household desktop.
