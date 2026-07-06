# dt

## Purpose
Builds and wires up `dt`, the DataX time tracker (CLI + TUI, vendored TypeScript source built via buildNpmPackage): clock in/out, invoicing config, stale-session and pomodoro timers, per-session .ics calendar output with khal integration. Enable via `hwc.home.apps.dt.enable`.

## Boundaries
- ✅ The `dt` package + `dt-stale-notifier`, `~/.config/dt/config.toml` (name/rate/max hours/poll/pomodoro), `dt-stale-check` and `dt-pomodoro` user services+timers, calendar dir activation, injection of a `dt-sessions` calendar into `hwc.mail.calendar.localCalendars` when khal integration is on.
- ❌ The waybar widget and SUPER+T/toggle keybinds are consumed by the waybar and hyprland modules (this module only exposes the `waybar.enable`/`hyprland.*` flags and asserts those apps are enabled); the sqlite DB and invoices are runtime data, not managed here.

## Structure
- `index.nix` — options (`enable`, `settings.*`, `waybar`, `hyprland.*`, `pomodoro.*`, `calendar.*`, `staleCheck.*`), config.toml, timers, khal wiring, assertions.
- `parts/package.nix` — buildNpmPackage derivation (esbuild bundle, node wrapper, better-sqlite3 toolchain).
- `source/` — vendored TypeScript source (CLI, TUI, db, pdf invoice, calendar libs).

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
