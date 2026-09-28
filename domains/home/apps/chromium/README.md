# chromium

## Purpose
Installs Chromium with proprietary codecs/WideVine (`enableWideVine = true`) plus the `chromium-hwc` launcher wrappers that pin rendering to the compositor's GPU (Intel, ANGLE-on-GL) on hybrid-GPU Wayland hosts, and registers it as the default browser. Enable via `hwc.home.apps.chromium.enable` (HM) and `hwc.system.apps.chromium.enable` (system lane).

## Boundaries
- ✅ HM lane: overridden chromium package, `chromium-hwc` + `chromium-hwc-workbench` wrappers (separate `--user-data-dir` profile for workbench), desktop entry, xdg-mime default-browser registration. System lane: dconf/dbus enables a managed policy (`RestoreOnStartup=1`) under `/etc/chromium/policies/managed/`, and a tmpfiles `x` rule protecting the `/tmp` singleton files.
- ❌ Does not manage GPU drivers or the gpu-toggle machinery (system hardware domain); no extensions, profiles content, or per-site settings.

## Structure
- `index.nix` — HM options, package override, desktop entry, mimeApps defaults, sys-lane assertion.
- `sys.nix` — system-lane option, dconf/dbus, session-restore managed policy, tmpfiles exclusion keeping the `/tmp` profile-singleton files from 10-day aging.
- `parts/launcher.nix` — `mkLauncher` building the two wrappers with GPU-safe flags and VA-API driver selection.

## Changelog
- 2026-09-28: Exclude `/tmp/org.chromium.Chromium.*/Singleton*` from tmpfiles aging. The 10-day `/tmp` rule deleted a long-running instance's `SingletonCookie`, so a new launch took the profile lock alongside it and both browsers stacked "Something went wrong when opening your profile" dialogs.
- 2026-09-12: Run both launchers through the system-owned `gpu-integrated` boundary when available, preventing Chromium's GPU process from opening NVIDIA during Vulkan/GL device enumeration while retaining Intel acceleration.
- 2026-09-12: Preserve the system-owned Mesa EGL vendor selection in both launchers while continuing to strip PRIME offload variables; deleting the EGL selection made Intel-rendered Chromium probe and hold the NVIDIA device.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
