# chromium

## Purpose
Installs Chromium with proprietary codecs/WideVine (`enableWideVine = true`) plus the `chromium-hwc` launcher wrappers that pin rendering to the compositor's GPU (Intel, ANGLE-on-GL) on hybrid-GPU Wayland hosts, and registers it as the default browser. Enable via `hwc.home.apps.chromium.enable` (HM) and `hwc.system.apps.chromium.enable` (system lane).

## Boundaries
- ✅ HM lane: overridden chromium package, `chromium-hwc` + `chromium-hwc-workbench` wrappers (separate `--user-data-dir` profile for workbench), desktop entry, xdg-mime default-browser registration. System lane: dconf/dbus enables and a managed policy (`RestoreOnStartup=1`) under `/etc/chromium/policies/managed/`.
- ❌ Does not manage GPU drivers or the gpu-toggle machinery (system hardware domain); no extensions, profiles content, or per-site settings.

## Structure
- `index.nix` — HM options, package override, desktop entry, mimeApps defaults, sys-lane assertion.
- `sys.nix` — system-lane option, dconf/dbus, session-restore managed policy.
- `parts/launcher.nix` — `mkLauncher` building the two wrappers with GPU-safe flags and VA-API driver selection.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
