# Mail Tasks (VTODO sync + todoman)

## Purpose
Sync tasks between the machines and Apple Reminders on the phone, using
iCalendar VTODO `.ics` files as the source of truth. vdirsyncer mirrors a local
vdir ↔ the self-hosted Radicale server (the phone reads the same server through
its CalDAV account), and `todoman` is the reference CLI for reading/writing tasks.

## Boundaries
- Manages: the `tasks_radicale` vdirsyncer pair (VTODO), the local
  `~/.local/share/vdirsyncer/tasks-radicale` vdir, todoman's `config.py`, the
  `email-to-task` review helper, and `~/.cache/todoman`.
- Does NOT manage: its own vdirsyncer config file or sync timer. It contributes
  a `[pair tasks_radicale]` fragment to `hwc.mail.calendar.extraVdirsyncerPairs`,
  so there is exactly one `~/.config/vdirsyncer/config` and one
  `vdirsyncer.service`/timer (owned by `domains/mail/calendar/`). Requires
  `hwc.mail.calendar.enable = true`.
- The TUI is `todui` (`domains/home/apps/todui`), which follows `hwc.mail.tasks.enable`.

## Structure
```
tasks/
├── index.nix                   # Module: options hwc.mail.tasks.*, todoman pkg,
│                               #   config.py, dir activation, pair contribution
└── parts/
    ├── vdirsyncer-pair-radicale.nix # [pair tasks_radicale] — "from a"/"from b"
    │                                #   discovery (list creation works)
    ├── todoman-config.nix           # ~/.config/todoman/config.py text
    └── email-to-task.py             # aerc email → reviewed MCP task handoff
```

## Default list
`hwc.mail.tasks.defaultList` defaults to `hwc.mail.calendar.primaryCalendar`
(`hwc`): todoman matches the displayname, and eric/work is shared with the
calendar. The MCP's `hwc_tasks_add` uses the same name (`DEFAULT_LIST` in
`domains/system/mcp/src/src/tools/tasks.ts`).

## Historical: iCloud VTODO go/no-go (2026-06-11, laptop)
The iCloud pair this section tested was deleted 2026-09-24. Kept as the record
of why discovery is pinned on the calendar pair and why CATEGORIES are trusted.
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

## Radicale backend
The `tasks_radicale` pair runs against the self-hosted Radicale server
(`domains/server/services/radicale/`, Caddy vhost tasks.hwc.iheartwoodcraft.com).
It auto-discovers collections both ways, so locally created lists (todui `N`)
are created server-side. Local vdir: `~/.local/share/vdirsyncer/tasks-radicale/`;
credential: the configured user's entry in the shared `radicale-htpasswd`
agenix secret, selected by `domains/lib/hm.nix`. Phone CalDAV setup: see the
radicale README.

## Changelog
- 2026-09-24: Radicale is the only backend. Deleted the iCloud pair
  (`parts/vdirsyncer-pair.nix`) and the `icloud.enable`, `account`,
  `collections`, and `radicale.enable` options, plus the apple-app-pw handshake.
  `icloud.enable` defaulted to true and the server never turned it off, so its
  vdirsyncer failed every run and server-side `todo` wrote into the dead
  `tasks/` store. todoman now reads only `tasks-radicale/*`, and `defaultList`
  follows `hwc.mail.calendar.primaryCalendar` (`hwc`) because `Work` matched no
  collection. `flake.nix` `radicale-client-auth` now checks both machines.
- 2026-09-15: Default new tasks to the Radicale Work collection. The reviewed
  email handoff prefers Work while retaining legacy `work`/`hwc` fallbacks
  during the collection migration.
- 2026-09-14: Added `email-to-task`, the reviewed aerc `t` handoff. It sends
  summary/list/due/categories/priority plus source context through
  `hwc_tasks_add`, using Message-ID (or a raw-message digest) as the stable
  idempotency key. It never archives mail and never retries an ambiguous write.
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
