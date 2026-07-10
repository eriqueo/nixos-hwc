# domains/mail/calendar

Calendar sync substrate: a single vdirsyncer config + user timer feeding khal
(now **khalt's** `khal`/`ikhal` fork). Owns the shared vdirsyncer config that
sibling modules (e.g. `domains/mail/tasks`) inject pairs into via
`hwc.mail.calendar.extraVdirsyncerPairs`.

NAMESPACE: `hwc.home.apps`-adjacent but lives under mail — `hwc.mail.calendar.*`.

## Backends

- **iCloud (legacy, default off-path):** one CalDAV pair per
  `hwc.mail.calendar.accounts.<name>` against `caldav.icloud.com`, discovery
  `["from a"]` (iCloud can't MKCALENDAR). Synced into `calendars/<account>/`.
- **Radicale (`hwc.mail.calendar.radicale.enable`):** the self-hosted CalDAV
  server (`tasks.hwc.iheartwoodcraft.com`, same vhost + `radicale-htpasswd`
  secret as the tasks backend). One VEVENT pair (`calendar_radicale`),
  discovery `["from a","from b"]` (Radicale allows MKCALENDAR), synced into
  `calendars-radicale/`. **When radicale is on, the iCloud account pairs are no
  longer generated** (calendar lives on Radicale, plumbed exactly like tasks).
  This is the VEVENT twin of `domains/mail/tasks`'s VTODO Radicale pair.

khalt's `khal` is THE calendar binary (plain `pkgs.khal` is retired); the
config at `~/.config/khal/config` and khalt's own `~/.config/khalt/config`
(see `domains/home/apps/khalt`) both point at the same calendar dirs.

## Migration (iCloud → Radicale, one-time, laptop)

`scripts/migrate-icloud-to-radicale.sh` copies existing iCloud VEVENT `.ics`
files into a local Radicale collection, then prints the `vdirsyncer discover` /
`sync` steps. Run AFTER `hms` with `radicale.enable = true`. It deletes nothing
and is idempotent. See the header comment in the script for the exact runbook.

## Structure

```
domains/mail/calendar/
├── index.nix                          # hwc.mail.calendar.* options + impl
├── parts/
│   ├── vdirsyncer.nix                 # single config (iCloud pairs OR radicale)
│   ├── vdirsyncer-pair-radicale.nix   # [pair calendar_radicale] (VEVENT)
│   ├── khal.nix                        # ~/.config/khal/config (palette-driven)
│   ├── service.nix                     # 15-min sync timer
│   ├── parser.nix                      # email-to-khal helper + aerc filter
│   ├── ics-watcher.nix                 # auto-import dropped .ics
│   └── email-to-khal.py
├── scripts/
│   └── migrate-icloud-to-radicale.sh  # one-time data migration (do not commit-run)
└── README.md
```

## Changelog

- **2026-07-10**: Booking accuracy. Set khal `default_calendar = migrated`
  (the VEVENT calendar the hwc-crm availability endpoint reads) when Radicale is
  on, so quick-adds never prompt. Added a `busy` command (`home.packages`):
  `busy <start> [end|dur] [summary]` → `khal new -a migrated` + immediate
  `vdirsyncer sync` so availability updates now, not on the ~15-min timer.
- **2026-06-15**: Calendar → Radicale. Added `hwc.mail.calendar.radicale.*`
  (enable/url/username/color); when on, `vdirsyncer.nix` suppresses the iCloud
  account pairs and emits `[pair calendar_radicale]` (VEVENT, "from a"/"from b",
  `b wins`, htpasswd via direct `cut`), mirroring the tasks Radicale pair.
  `khal.nix` + the khalt app render a `[[radicale]]` discover calendar (and drop
  the stale iCloud account calendars) under `calendars-radicale/`; the iCloud
  `default_calendar` UUID is omitted under radicale. **Retired plain
  `pkgs.khal`** — the domain now installs khalt's package
  (`inputs.khalt.packages.<system>.default`), whose `khal` binary backs
  waybar/todui/ics-watcher/the MCP. Accounts assertion relaxed to allow
  radicale-only (no iCloud account). Added the one-time migration script.
  Companion to `domains/system/mcp` (hwc_calendar→khalt) and
  `domains/home/apps/khalt`.
