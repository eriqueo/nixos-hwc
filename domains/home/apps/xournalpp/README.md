# xournalpp

## Purpose
Installs Xournal++, a PDF annotator and handwritten note-taker. A one-package
module generated via `domains/lib/mkSimpleApp.nix` — no configuration is
managed here.

## Boundaries
- ✅ Installs `pkgs.xournalpp` when `hwc.home.apps.xournalpp.enable = true`
- ❌ No app settings, templates, or stylus configuration — managed by the app at runtime
- ❌ Not the default PDF viewer — zathura is wired in thunar's mimeApps

## Structure
- `index.nix` — mkSimpleApp call declaring name, description, and package

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
