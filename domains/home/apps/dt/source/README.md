# dt — DataX Time Tracker

CLI + TUI + Waybar time tracker for invoicing DataX.

## Quick Start

```bash
# Install dependencies
npm install

# Copy config
mkdir -p ~/.config/dt
cp config.example.toml ~/.config/dt/config.toml

# Run via tsx (dev)
npx tsx src/cli/index.ts in support
npx tsx src/cli/index.ts status
npx tsx src/cli/index.ts out -n "triaged tickets"
npx tsx src/cli/index.ts log
npx tsx src/cli/index.ts tui

# Build
node build.mjs
node dist/dt.mjs status
```

## Commands

| Command | Description |
|---------|-------------|
| `dt in [category]` | Clock in |
| `dt out [-n notes] [-c cat]` | Clock out |
| `dt toggle [category]` | Toggle (Waybar click) |
| `dt status [--waybar\|--json]` | Current state |
| `dt log [today\|yesterday\|YYYY-MM-DD]` | Day log |
| `dt week [-b N]` | Weekly summary |
| `dt month [-b N]` | Monthly summary |
| `dt amend <last\|ID> [--start --end -c -n]` | Edit session |
| `dt export --from YYYY-MM-DD --to YYYY-MM-DD` | Generate PDF invoice |
| `dt stale-check` | Notify if session stale (systemd) |
| `dt tui` | Interactive terminal UI |

## TUI Keys

- `i` — clock in
- `o` — clock out (prompts notes + category)
- `1/2/3` or `tab` — switch tabs (Dashboard / History / Export)
- `q` — quit

## Data

- Config: `~/.config/dt/config.toml`
- Database: `~/.local/share/dt/dt.sqlite`
- Invoices: `~/Documents/datax-time/`

## NixOS

See `INTEGRATION.md` for Waybar, Hyprland, and NixOS module setup.

## Structure

```
source/
├── build.mjs              # esbuild bundle
├── config.example.toml
├── INTEGRATION.md         # Waybar, Hyprland and NixOS wiring
├── package.json, package-lock.json, tsconfig.json
└── src/
    ├── cli/               # amend, calendar-rebuild, doctor, export, in, log, out,
    │                      #   pomodoro-check, snooze, stale-check, status, toggle
    ├── config/            # config loader
    ├── db/                # connection, schema, queries
    ├── lib/               # calendar, snooze, time, types
    ├── pdf/invoice.ts
    ├── tui/               # Ink TUI screens
    └── __tests__/read-paths.test.ts
```

## Changelog

- 2026-11-04: `db/queries.ts` selects explicit columns for active sessions and
  invoice/category/day summaries (timer and status readers no longer load
  notes); `cli/amend.ts` and `cli/calendar-rebuild.ts` follow. Fixed regexes in
  the CLI, `lib/calendar.ts`, `lib/time.ts` and `tui/Export.tsx` move to module
  scope. New `__tests__/read-paths.test.ts` checks SQLite results with an
  unused large column present; `parts/package.nix` runs it as the package
  `checkPhase` (68ff8eda).
