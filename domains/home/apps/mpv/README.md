# mpv

## Purpose
Configures the mpv media player via `programs.mpv` for couch/TV-style playback: hardware decoding (`hwdec = auto`), fullscreen by default, raised volume ceiling, and controller-friendly arrow-key bindings (volume/seek).

## Boundaries
- ✅ Manages: `hwc.home.apps.mpv.enable` → mpv install, `config` block, and arrow-key `bindings`.
- ❌ Does not manage: mpv scripts/shaders, MIME default-app associations, or the idle-inhibit window rule (that lives in `domains/home/apps/hyprland/parts/behavior.nix`).

## Structure
The single module owns the package and configuration directly; it has no validation-only output block.

- `index.nix` — options + `programs.mpv` config and bindings.

## Changelog
- 2026-11-09: Remove empty assertion scaffolding; preserve package and configuration output.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
