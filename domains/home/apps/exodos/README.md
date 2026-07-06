# exodos

## Purpose
Integrates the eXoDOS DOS game collection: an activation script auto-installs the retro_exo flatpak runtimes/packages from the collection on `switch`, and a desktop entry launches `exogui`. Enable via `hwc.home.apps.exodos.enable`.

## Boundaries
- ✅ Guarded `home.activation` step (adds flathub remote, installs freedesktop/GNOME/KDE runtimes and the bundled *.flatpak files; no-op until the collection exists and skips if already installed) and the `exogui` desktop entry pointing into `root` (default `~/eXoDOS`).
- ❌ The collection data itself is unmanaged — the user drops it at `root`; system flatpak support comes from elsewhere (`/run/current-system/sw/bin/flatpak` must exist).

## Structure
- `index.nix` — options (`enable`, `root`), flatpak activation script, desktop entry.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
