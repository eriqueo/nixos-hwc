# proton-pass

## Purpose
Installs the Proton Pass desktop client. Its native colored tray icon opens the app from Waybar.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-pass.enable` → desktop package with Linux tray activation wired to its existing open handler.
- ❌ Does not manage: the app's own runtime config at `~/.config/Proton Pass/` (app needs write access; theme set manually in-app), vault data/credentials, browser extensions, or window rules (in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — enable option and package wiring.
- `parts/session.nix` — desktop package and Linux tray click patch. `postInstall` unpacks
  `app.asar` with `asar`, `substituteInPlace --replace-fail`s the tray handler in
  `.webpack/main/index.js`, and repacks. `--replace-fail` means an upstream change fails the
  build instead of silently dropping the patch.

## Changelog
- 2026-09-26: Narrowed the tray patch's match to the single line
  `tray.on('double-click', onOpenPassHandler);` and appended the Linux `click` registration
  after it, instead of matching the two-line `if (process.platform === 'win32')` block and
  rewriting it. The multi-line match depended on upstream's exact indentation and branch
  ordering; the one-liner is the stable anchor.
- 2026-09-26: Wired Linux tray activation to Proton Pass's existing open handler. The upstream bundle only registered a Windows double-click handler, so Waybar's left-click activation did nothing.
- 2026-09-26: Removed the unused `~/.config/protonpass/config.json` producer and inert options. Proton Pass keeps its real writable config.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
