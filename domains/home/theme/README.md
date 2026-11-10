# Home Theme

## Purpose
Single source of truth for look-and-feel: color palettes materialized as
token sets, GTK/Qt theming, fonts, and pointer cursor.

## Boundaries
- Manages: `hwc.home.theme.*` (palette, colors, cursor, icons, gtkTheme,
  typography, fonts.{enable,mono,ui}), GTK 2/3/4 + Qt platform theming.
- Does NOT manage: per-app color consumption — apps read the guarded
  token set themselves (see canonical accessor below).

## Structure
`palettes/common.nix` owns identical cursor and alpha facts. Each palette owns its color vocabulary and derives semantic aliases from its own tokens. The selectable palette names come from the palette table.

The palette supplies both XCursor and native Hyprcursor tokens. Hyprland links native assets from the installed cursor package.
```
theme/
├── index.nix        # Options + palette materialization + qt platform theme
├── palettes/        # deep-nord.nix, gruv.nix, hwc.nix (token sets incl.
│                    #   ansi, sectionA-D powerline tokens, cursor block)
├── templates/
│   └── gtk.nix      # GTK/CSS bridge; cursor and dconf activation follow graphical
├── fonts/index.nix  # font packages + mono/ui font-name tokens
└── nord-mountains.jpg
```

## How it works
1. `hwc.home.theme.palette` selects a palette (default `hwc`).
2. `index.nix` materializes it as `hwc.home.theme.colors` and wires the
   palette's cursor block into `hwc.home.theme.cursor` (both cursor formats).
3. Apps consume tokens via the guarded read:
   `(config.hwc.home.theme or {}).colors or {}` — never by importing
   palette files directly.
4. `templates/gtk.nix` (auto-imported) applies GTK/Qt/cursor/icon theming
   for every HM host; `fonts/index.nix` is gated on `theme.fonts.enable`.

There is no separate "adapters" layer — that design was never built; the
former README describing it was aspirational.

## Changelog

- 2026-11-09: Share identical palette facts and derive semantic aliases without changing token values.
- 2026-11-04: Repair declarative desktop cursor, mouse bindings, physical-output selection and Waybar reload supervision; extend generated desktop checks.
- 2026-09-24: Default dconf activation to `theme.graphical`, preserving file-based GTK settings while avoiding desktop D-Bus writes on headless hosts. Fixes first activation of `hwc-work` without a dconf service.
- 2026-09-02: Explicitly enable `home.pointerCursor` on graphical hosts,
  preserving the existing cursor output without Home Manager's deprecated
  implicit-enable behavior.
- 2026-06-11: Add `theme.graphical` option (default true). When false, the
  gtk template skips the GUI-only XCursor theme (~846 MB) and pointer-cursor
  wiring — headless machines (hwc-server) set it false in their machine home
  one-off, mirroring `theme.fonts.enable`. Graphical machines unchanged.
- 2026-06-11: Rewritten to describe the real architecture (options +
  materialized tokens + gtk template), replacing the phantom-adapters
  meta-summary. cursor/icons/gtkTheme/typography options are now declared;
  sectionA-D and fonts.mono/ui tokens added.
