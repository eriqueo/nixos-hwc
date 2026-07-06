# swaync

## Purpose
Configures the SwayNC notification center via `services.swaync`: installs
`swaynotificationcenter` and supplies settings plus palette-driven CSS from
the appearance part.

## Boundaries
- ✅ `hwc.home.apps.swaync.enable`; swaync settings (position, layers, margins, widget behavior) and style, themed from `hwc.home.theme` (colors + UI font)
- ❌ Not the waybar notification widget itself — waybar only requires swaync be enabled (`domains/home/apps/waybar/`)
- ❌ No system-level notification daemon wiring beyond the HM service

## Structure
- `index.nix` — options, package install, `services.swaync` wiring
- `parts/appearance.nix` — settings attrset + CSS style derived from theme tokens

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
