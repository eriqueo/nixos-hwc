# proton-pass

## Purpose
Installs the Proton Pass desktop client. Its native colored tray icon opens the app from Waybar.

## Boundaries
- ✅ Manages: `hwc.home.apps.proton-pass.enable` → desktop package with Linux tray activation wired to its existing open handler.
- ❌ Does not manage: the app's own runtime config at `~/.config/Proton Pass/` (app needs write access; theme set manually in-app), vault data/credentials, browser extensions, or window rules (in `domains/home/apps/hyprland`).

## Structure
- `index.nix` — enable option and package wiring.
- `parts/session.nix` — desktop package and Linux tray click patch. The exact-match patch fails the build if Proton changes the bundled handler.

## Changelog
- 2026-09-26: `parts/session.nix` matches the single line
  `tray.on('double-click', onOpenPassHandler);` and appends the Linux `click`
  registration after it, instead of matching that line together with its enclosing
  `if (process.platform === 'win32')`. The two-line match was the fragile half of the
  patch — any upstream reflow of the surrounding block would fail
  `--replace-fail` (`b3c8e5dc`).
- 2026-09-26: Wired Linux tray activation to Proton Pass's existing open handler. The upstream bundle only registered a Windows double-click handler, so Waybar's left-click activation did nothing.
- 2026-09-26: Removed the unused `~/.config/protonpass/config.json` producer and inert options. Proton Pass keeps its real writable config.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
