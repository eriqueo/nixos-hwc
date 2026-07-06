# thunar

## Purpose
Installs the Thunar file manager with its plugin/thumbnail stack (volman,
archive, media-tags, tumbler, gvfs, file-roller) and sets XDG default
applications for directories, archives, text (micro), and PDF (zathura).

## Boundaries
- ✅ `hwc.home.apps.thunar.enable`; packages, `xdg.mimeApps` defaults, `FILE_MANAGER`/`TERMINAL` session vars, `xfce4/helpers.rc` (kitty as terminal)
- ✅ Seeds `thunar.xml` xfconf defaults once via activation — Thunar owns the file afterward, so runtime tweaks survive rebuilds
- ✅ Unconditional `micro.desktop` entry (defined even when thunar is disabled, to avoid a missing-value error in mimeApps consumers)
- ❌ Not the terminal file manager — see `domains/home/apps/yazi/`

## Structure
- `index.nix` — options, packages, mimeApps, session vars, xfconf seed activation

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
