# todui — VTODO task TUI (external program, HWC adapter)

## Purpose
Thin HWC integration for **todui**, the standalone keyboard task TUI that
lives in its own repo at `~/dev/todui` and is consumed here as the `todui`
flake input. This module translates HWC config into todui's generic Home
Manager options: the system theme palette, the Radicale CalDAV endpoint +
agenix secret, and the vdir paths. todui itself is todoman-free and knows
nothing about HWC.

This replaces the former in-tree `tasq` (module `domains/home/apps/tasq/` +
sources under `workspace/home/tasq/`), which was pinned to this repo. todui
owns its own engine, tests, packaging, and release cadence.

## Boundaries
- Manages: `programs.todui.*` settings derived from HWC config; nothing else.
- Does NOT manage: the todui program (its repo/flake), the vdir, vdirsyncer,
  or the Radicale server. The vdir + sync are owned by `domains/mail/tasks/`;
  the server by `domains/server/services/radicale/`.
- The program builds from the `todui` flake input, currently a **live-dev
  `path:` input** (`~/dev/todui`) — source edits land on the next `hms`. Not
  reproducible and not buildable on hwc-server until the input is pinned to a
  git rev (see flake.nix `todui` input comment).

## Structure
```
todui/
└── index.nix     # imports inputs.todui.homeManagerModules.todui;
                  #   options hwc.home.apps.todui.enable;
                  #   maps theme palette + radicale creds + paths → programs.todui
```

## Integration points
- Palette: `config.hwc.home.theme.colors` → `programs.todui.palette` (todui
  derives its UI roles from these tokens; switching the system palette
  restyles todui on next `hms`).
- Radicale: `hwc.mail.tasks.radicale.{url,username}` + the `radicale-htpasswd`
  agenix secret → `programs.todui.radicale.*` (enables in-app list deletion via
  CalDAV DELETE).
- Paths/sync: derived from `hwc.mail.tasks.radicale.enable` and the vdir root.
- khal + vdirsyncer are put on todui's PATH via `extraRuntimePackages`.

## Changelog
- 2026-06-12: Launcher integration — `xdg.desktopEntries.todui` (`kitty -e
  todui`, terminal=false) so it appears in wofi/rofi `drun`; Hyprland keybind
  `SUPER+T` added in `domains/home/apps/hyprland/parts/behavior.nix` (gated on
  `hwc.home.apps.todui.enable`). The `dt` (DataX TUI) keybind moved `SUPER+T`
  → `SUPER+D` to free `T` for tasks.
- 2026-06-12: Created. Replaces the in-tree `tasq` module and
  `workspace/home/tasq/` sources with the standalone `todui` flake input
  (live-dev `path:` input at `~/dev/todui`). Full keyboard parity (leader
  menus, list/project/context management, CalDAV list deletion, week strip);
  read/write VTODO parity with the prior todoman-backed engine verified
  against real data. Profile enable flipped `tasq.enable` → `todui.enable`.
