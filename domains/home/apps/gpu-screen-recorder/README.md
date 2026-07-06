# gpu-screen-recorder

## Purpose
GPU-encoded screen recording for calls. The HM lane ships only the `gsr-toggle` start/stop script (runs the recording as a transient `gsr-record` user unit) and `gsr-status` (waybar JSON); the system lane provides the actual binary via `programs.gpu-screen-recorder` with the setcap'd `gsr-kms-server` wrapper for promptless Wayland capture. Enable via `hwc.home.apps.gpu-screen-recorder.enable` + `hwc.system.apps.gpu-screen-recorder.enable`.

## Boundaries
- ✅ HM: `gsr-toggle` (focused-monitor capture at `fps`, merged `audio` sources, output under `hwc.paths.recordings` with a standalone-HM fallback, waybar RTMIN+9 refresh) and `gsr-status`. Sys: the nixpkgs `programs.gpu-screen-recorder` enable.
- ❌ HM deliberately does NOT install the plain package (it would shadow the setcap wrapper and break promptless capture); the SHIFT+PRINT keybind and waybar widget are wired in the hyprland and waybar modules.

## Structure
- `index.nix` — HM options (`enable`, `fps`, `audio`), gsr-toggle/gsr-status scripts.
- `sys.nix` — system-lane option enabling `programs.gpu-screen-recorder` (setcap wrapper).

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
