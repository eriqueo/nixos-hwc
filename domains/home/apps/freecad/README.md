# freecad

## Purpose
Installs FreeCAD (patched with an Arch-workbench window-displaymode guard) with GPU-aware launch wrappers — `freecad-gpu` (NVIDIA PRIME offload) or `freecad-optimized` (Intel/AMD) picked from the host's `hwc.system.hardware.gpu` config — and seeds a one-time `user.cfg` enabling VBO/Core-Profile/MSAA rendering. Enable via `hwc.home.apps.freecad.enable`.

## Boundaries
- ✅ Patched `pkgs.freecad`, the two wrappers (gated on `gpuAcceleration` + GPU type), a desktop entry exec'ing the right wrapper, and a copy-not-symlink initial `~/.config/FreeCAD/user.cfg` (only if absent — user changes preserved).
- ❌ Does not manage GPU drivers or `hwc.system.hardware.gpu` (system domain); after first run the user.cfg is FreeCAD's to mutate, not Nix's.

## Structure
- `index.nix` — options (`enable`, `gpuAcceleration`), patched package, wrappers, desktop entry, seed-once activation, GPU assertion.
- `patches/arch-window-displaymode-guard.patch` — upstream FreeCAD source patch.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
