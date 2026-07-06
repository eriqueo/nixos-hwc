# wasistlos

## Purpose
Installs WasIstLos, a WhatsApp desktop client. A one-package module generated
via `domains/lib/mkSimpleApp.nix` — no configuration is managed here.

## Boundaries
- ✅ Installs `pkgs.wasistlos` when `hwc.home.apps.wasistlos.enable = true`
- ❌ No account setup or app settings — managed by the app at runtime

## Structure
- `index.nix` — mkSimpleApp call declaring name, description, and package

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
