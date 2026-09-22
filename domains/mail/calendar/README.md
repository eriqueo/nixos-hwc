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
  secret as the tasks backend). One VEVENT pair (`calendar_radicale`) pinned to
  `work`, `family`, and `personal`, synced into `calendars-radicale/`.
  The `work` collection keeps the stable khal display name `hwc`; collection
  paths and user-facing display names are separate contracts.
  **When radicale is on, the iCloud account pairs are no
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
│   ├── email-to-khal.py                # reviewed email → event proposal/import
│   └── email_to_khal_test.py           # parser, flyer, and fetch-policy regressions
├── scripts/
│   └── migrate-icloud-to-radicale.sh  # one-time data migration (do not commit-run)
└── README.md
```

## Changelog

- 2026-09-21: `hwc.mail.calendar.radicale.extraCollections` — further VEVENT
  collection ids pinned into the `calendar_radicale` pair, for the read-only
  mirrors the server keeps in Radicale (`hwc.server.services.radicale.mirrors`:
  `cto`, `proton-work`, `google-family`). Both machines list them; khal picks
  the new dirs up through its `calendars-radicale/*` discovery. Edits to a
  mirrored event are reverted by the next server mirror run.

- 2026-09-21: `email-to-khal --draft PATH` now writes a private, reviewable
  khal-format proposal without importing or syncing. Classifier automation
  deliberately ignores attachment contents.

- **2026-09-15**: Restored `hwc` as the primary business calendar's stable
  display name after the collection taxonomy rollout changed khal's generated
  default to `Work`. The collection path remains `eric/work`; khal's default
  and `busy` now derive from one `hwc` value. This keeps aerc's reviewed `i`
  import and booking blocks on the same calendar.

- **2026-09-15**: Replaced the flattened `migrated`/`hwc` calendar target with
  the human-readable Work, Family, and Personal collections. khal and `busy`
  now default to Work; the VEVENT sync pair excludes task-only Groceries.

- **2026-09-14**: Image-based newsletter proposals now recover a written date
  from the subject while leaving an unknown time blank for review. The helper
  removes a duplicated trailing date from the title, never treats a generic or
  campaign-tracked URL as the venue, and reduces the raw URL wall to one
  labeled event-page candidate. Link selection remains offline and never
  resolves campaign redirects. If facts remain missing inside a large remote
  flyer, an explicit prompt can fetch one public HTTPS image (no redirects,
  8-MiB cap, bounded network/OCR time, no retry) and run local Tesseract; its
  proposed time, duration, and venue remain editable before import.
- **2026-09-14**: Made the aerc `i` handoff outcome honest: cancellation no
  longer falls through to a sync/success message, sync names the configured
  calendar server rather than iCloud, and success tells the operator to archive
  the unchanged source email with `a`. A failed sync reports that the event is
  already local and must not be created again.
  Compact school-message ranges such as `5:30p-6:30p 9/17/26` now produce the
  start and 60-minute duration in the review form automatically.
  HTML-only messages now put cleaned readable text in the reference section;
  the previous branch leaked raw HTML markup into the editor.
- **2026-07-10**: Booking accuracy. Set khal `default_calendar = migrated`
  (the VEVENT calendar the hwc-crm availability endpoint reads) when Radicale is
  on, so quick-adds never prompt. Added a `busy` command (`home.packages`):
  `busy <start> [end|dur] [summary]` → `khal new -a migrated` + immediate
  `vdirsyncer sync` so availability updates now, not on the ~15-min timer.
- **2026-07-10** (follow-up): Set the calendar's CalDAV displayname to `hwc`
  (was blank → clients showed the raw collection id "migrated"). khal identifies
  calendars BY displayname, so `default_calendar` and the `busy` command now use
  `-a hwc` (superseding the `-a migrated` above), while the Radicale collection
  PATH stays `cal/migrated` — the hwc-crm availability endpoint + event PUTs use
  the URL path and are unaffected. Displayname was set on the local vdir side and
  pushed via `vdirsyncer metasync` (pair `conflict_resolution = "b wins"` = local
  wins on push). iPhone/khal now display "hwc".
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
