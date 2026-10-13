# vectorcraft

## Purpose
Installs VectorCraft, the open-source Illustrator-style vector editor, from our fork
`github:eriqueo/vectorcraft` (branch `hwc/main`). The fork is where GIS map-finishing
improvements land; see the `vectorcraft-gis-feasibility` project.

## Boundaries
- ✅ Installs the fork's package (`vectorcraft`, `vectorcraft-cli`, launcher entry, icons, MIME types) when `hwc.home.apps.vectorcraft.enable = true`
- ❌ No build logic: the derivation lives in the fork's `flake.nix`
- ❌ No app settings: VectorCraft keeps its own preferences under `~/.config`
- ❌ Not the default SVG/PDF handler: the package registers its MIME types but sets no defaults

## Structure
- `index.nix` — `enable` option; installs `inputs.vectorcraft.packages.<system>.default`

## Changelog
- 2026-10-13: Module added; consumes the `vectorcraft` flake input (fork of storytold/vectorcraft). Enabled on hwc-laptop.
