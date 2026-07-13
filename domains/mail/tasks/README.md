# Mail Tasks (VTODO sync + todoman)

## Purpose
Sync tasks between the laptop and Apple Reminders on the phone, using iCalendar
VTODO `.ics` files as the source of truth. vdirsyncer mirrors a local vdir ↔
iCloud CalDAV (VTODO collections = Reminders), and `todoman` is the reference
CLI for reading/writing tasks.

## Boundaries
- Manages: the `tasks` vdirsyncer pair (VTODO), the local tasks vdir, todoman's
  `config.py`, and the `~/.cache/todoman` / `~/.local/share/vdirsyncer/tasks`
  directories.
- Does NOT manage: its own vdirsyncer config file or sync timer. It contributes
  a `[pair tasks]` fragment to `hwc.mail.calendar.extraVdirsyncerPairs`, so there
  is exactly one `~/.config/vdirsyncer/config` and one `vdirsyncer.service`/timer
  (owned by `domains/mail/calendar/`). Requires `hwc.mail.calendar.enable = true`.
- Does NOT (yet) provide a TUI — see Phase B (`todui`) in the project plan.

## Structure
```
tasks/
├── index.nix                   # Module: options hwc.mail.tasks.*, todoman pkg,
│                               #   config.py, dir activation, pair contribution
└── parts/
    ├── vdirsyncer-pair.nix          # [pair tasks] fragment (item_types = ["VTODO"])
    ├── vdirsyncer-pair-radicale.nix # [pair tasks_radicale] — self-hosted backend,
    │                                #   "from a"/"from b" discovery (list creation works)
    └── todoman-config.nix           # ~/.config/todoman/config.py text
```

## Secret + account
Reuses calendar's `apple-app-pw` agenix secret via the same handshake
(`osConfig.age.secrets.apple-app-pw.path`, falling back to
`/run/agenix/apple-app-pw` under standalone `hms`). The Apple ID email is taken
from `hwc.mail.calendar.accounts.<hwc.mail.tasks.account>` (default `icloud`).

## iCloud VTODO go/no-go (run on the laptop after first `hms`)
1. `hms` runs clean.
2. `cat ~/.config/vdirsyncer/config` shows both the calendar pairs and
   `[pair tasks]` with `item_types = ["VTODO"]`; password fetched from the secret
   path, not a literal.
3. `systemctl --user list-timers | grep vdirsyncer` → exactly one timer.
4. `vdirsyncer discover tasks` lists ≥1 VTODO/Reminders collection. Zero ⇒ no-go
   (fall back to self-hosted Radicale). If empty, try the per-dsid principal URL
   instead of bare `https://caldav.icloud.com/`. **Gotcha:** discovery returns
   ALL CalDAV collections — VEVENT calendars too — because vdirsyncer has no
   component filter for discovery (`item_types` only filters items at sync). If
   two collections share a display name (e.g. a "Family" calendar AND a "Family"
   reminders list), todoman aborts with *"More than one list has the same
   identity"*. Pin `hwc.mail.tasks.collections` to the VTODO collection IDs.
   Identify them with a `supported-calendar-component-set` PROPFIND per collection
   (look for `<comp name='VTODO'/>`); set the IDs in the machine one-off, then
   delete any stale VEVENT dirs left under `~/.local/share/vdirsyncer/tasks/` and
   reset `status/tasks.collections` before re-discovering.
5. `vdirsyncer sync tasks`, then
   `find ~/.local/share/vdirsyncer/tasks -name '*.ics' | xargs grep -l VTODO`.
6. Round-trip: `todo new -l <list> "vdir test from laptop"` → `vdirsyncer sync
   tasks` → confirm it appears in Apple Reminders on the phone; add a reminder on
   the phone → sync → `todo list`.
7. CATEGORIES check (feeds Phase B `todui` model mapping): confirm a
   `+project`/category survives the round-trip into Reminders. Record the result
   below — it decides whether Phase B encodes project/context via `CATEGORIES` or
   inline in the summary.
8. If `default_list` (`hwc.mail.tasks.defaultList`) doesn't match the discovered
   collection directory name, correct it and re-run `hms`.

**GO** only if discover lists a VTODO collection AND todoman→Reminders AND
Reminders→local all work.

### Go/no-go result (verified on hwc-laptop, 2026-06-11) — **GO**
- `vdirsyncer discover` exposed 2 VTODO collections: `36BB690C…` ("Reminders")
  and `D788714B…` ("Family"); the other 4 discovered collections are VEVENT and
  are excluded via `hwc.mail.tasks.collections`.
- Sync down pulled a real reminder ("Ryan's bday"); `todo list` reads it.
- Write: `todo new` → `vdirsyncer sync` uploaded the VTODO to iCloud (visible in
  Apple Reminders). Delete propagated too.
- **CATEGORIES round-trip: PRESERVED.** Apple stored `CATEGORIES:work,urgent` and
  `PRIORITY:1` intact through the round-trip → Phase B (`todui`) maps
  `+project/@context` to `Todo.categories` (no inline-summary fallback needed).

## Radicale backend (Phase C, optional)
`hwc.mail.tasks.radicale.enable` adds a second pair (`tasks_radicale`) against
the self-hosted Radicale server (`domains/server/services/radicale/`, Caddy
vhost tasks.hwc.iheartwoodcraft.com). Unlike iCloud it auto-discovers
collections both ways, so locally created lists (todui `N`) are created
server-side. Local vdir: `~/.local/share/vdirsyncer/tasks-radicale/`;
credential: the shared `radicale-htpasswd` agenix secret (password =
`cut -d: -f2-`). todoman's path glob widens to `tasks*/*` so both backends
stay CLI-visible. Deploy order + phone CalDAV setup: see the radicale README.

## Changelog
- 2026-07-13: separate Radicale principals for calendar (`cal`) vs tasks (`eric`)
  so each pair's dynamic discovery no longer grabs the other's collections. The
  shared htpasswd gains a `cal:` line, so `vdirsyncer-pair-radicale.nix` now
  extracts THIS user's password by username via a colon-safe `awk` fetch (gawk is
  on the service PATH) instead of a bare `cut -f2-`. (Not activated until the
  `cal:` line exists in the secret.)
- 2026-07-13: Radicale (VEVENT) calendar backend added + plain khal retired
  (`domains/mail/calendar/`); the tasks account/email assertion relaxed to fire
  only when `hwc.mail.tasks.icloud.enable` (Radicale-only setups may have no
  iCloud account at all).
- 2026-07-13: repaired vdirsyncer (`vdirsyncer.service` was exiting 1, killing
  both khalt calendar and todui tasks sync). Two fixes in
  `vdirsyncer-pair-radicale.nix`: run `cut` directly (no `sh -c` — the user
  service PATH has coreutils but not bash), and switch the iCloud pair to
  server-authoritative `["from a"]` so a stale local-only collection no longer
  404s every run. One-time `vdirsyncer discover` needed after deploy.
- 2026-06-11: Phase C plumbing — optional `radicale` sub-options + second
  vdirsyncer pair part (off by default; flip in machines/laptop/home.nix after
  the server deploy). todoman path glob parameterized (`tasks*/*` with radicale).
- 2026-06-11: Phase A verified GO on hwc-laptop. Added `hwc.mail.tasks.collections`
  to pin the pair to VTODO collections (vdirsyncer over-discovers VEVENT calendars,
  which broke todoman on a duplicate "Family" name); pinned the laptop to its two
  Reminders lists in `machines/laptop/home.nix`. Enabled tasks on the laptop there
  (it wires mail per-machine, not via the mail role). CATEGORIES confirmed to
  survive iCloud round-trip.
- 2026-06-11: Initial Phase A — vdirsyncer VTODO pair (contributed to the shared
  calendar config/timer) + todoman CLI and config. TUI (`todui`) deferred to Phase B.
