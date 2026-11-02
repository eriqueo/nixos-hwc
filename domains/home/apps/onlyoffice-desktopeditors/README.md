# onlyoffice-desktopeditors

## Purpose
Installs OnlyOffice Desktop Editors as a one-package Home Manager app via `domains/lib/mkSimpleApp.nix`, with an FHS-env override that adds `libGL` to the sandbox and launches with `--force-scale=1.25` for HiDPI rendering.

## Boundaries
- ✅ Manages: `hwc.home.apps.onlyoffice-desktopeditors.enable` → the overridden package on `home.packages` (buildFHSEnv targetPkgs + runScript tweaks).
- ❌ Does not manage: document defaults, MIME associations, or in-app settings.

## Structure
The package omits upstream's retired GTK2 build input while retaining GTK3/Qt,
strict autoPatchelf checks, libGL and the existing scale setting.
- `index.nix` — mkSimpleApp call with the `onlyoffice-desktopeditors.override` (libGL + forced scale).

## Changelog
- 2026-11-02: Remove the legacy GTK2 packaging input and require the actual vendor binary to pass strict dependency checks on the refreshed channel.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
