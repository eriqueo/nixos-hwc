# dt

## Purpose
Builds and wires up `dt`, the DataX time tracker (CLI + TUI, vendored TypeScript source built via buildNpmPackage): clock in/out, invoicing config, stale-session and pomodoro timers, per-session .ics calendar output with khal integration. Enable via `hwc.home.apps.dt.enable`.

## Boundaries
- ✅ The `dt` package + `dt-stale-notifier`, `~/.config/dt/config.toml` (name/rate/max hours/poll/pomodoro), `dt-stale-check` and `dt-pomodoro` user services+timers, calendar dir activation, injection of a `dt-sessions` calendar into `hwc.mail.calendar.localCalendars` when khal integration is on.
- ❌ The waybar widget and SUPER+T/toggle keybinds are consumed by the waybar and hyprland modules (this module only exposes the `waybar.enable`/`hyprland.*` flags and asserts those apps are enabled); the sqlite DB and invoices are runtime data, not managed here.

## Structure
`source/build.mjs` is the npm and Nix build producer; package metadata supplies the executable path. `source/src/__tests__/export.test.ts` exercises the built CLI and parses a real invoice PDF.

`source/src/db/queries.ts` accepts typed active-session projections. Timer/status readers omit notes; invoice summaries omit unused fields. `source/src/__tests__/read-paths.test.ts` checks SQLite results and summaries during package checks. Fixed CLI/calendar/export patterns live at module scope.
- `index.nix` — options (`enable`, `settings.*`, `waybar`, `hyprland.*`, `pomodoro.*`, `calendar.*`, `staleCheck.*`), config.toml, timers, khal wiring, assertions.
- `parts/package.nix` — buildNpmPackage derivation (esbuild bundle, node wrapper, better-sqlite3 toolchain).
- `source/` — vendored TypeScript source (CLI, TUI, db, pdf invoice, calendar libs).

## Changelog
- 2026-11-09: Remove the unused duplicate invoice renderer, share summary formatting, and make npm/Nix builds consume one manifest-driven bundle entry; test real CLI PDF export.
- 2026-11-02: Use explicit projections for active sessions, invoice summaries, amendments and calendar rebuilds; test real SQLite results and hoist fixed patterns.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
