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
```
theme/
├── index.nix        # Options + palette materialization + qt platform theme
├── palettes/        # deep-nord.nix, gruv.nix, hwc.nix (token sets incl.
│                    #   ansi, sectionA-D powerline tokens, cursor block)
├── templates/
│   └── gtk.nix      # palette -> GTK 2/3/4 settings, CSS bridge, pointerCursor
├── fonts/index.nix  # font packages + mono/ui font-name tokens
└── nord-mountains.jpg
```

## How it works
1. `hwc.home.theme.palette` selects a palette (default `hwc`).
2. `index.nix` materializes it as `hwc.home.theme.colors` and wires the
   palette's cursor block into `hwc.home.theme.cursor` (xcursor only —
   hyprcursor assets are not in the repo; backlog).
3. Apps consume tokens via the guarded read:
   `(config.hwc.home.theme or {}).colors or {}` — never by importing
   palette files directly.
4. `templates/gtk.nix` (auto-imported) applies GTK/Qt/cursor/icon theming
   for every HM host; `fonts/index.nix` is gated on `theme.fonts.enable`.

There is no separate "adapters" layer — that design was never built; the
former README describing it was aspirational.

## Changelog
- 2026-06-11: Rewritten to describe the real architecture (options +
  materialized tokens + gtk template), replacing the phantom-adapters
  meta-summary. cursor/icons/gtkTheme/typography options are now declared;
  sectionA-D and fonts.mono/ui tokens added.
