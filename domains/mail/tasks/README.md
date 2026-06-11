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
- Does NOT (yet) provide a TUI — see Phase B (`tasq`) in the project plan.

## Structure
```
tasks/
├── index.nix                   # Module: options hwc.mail.tasks.*, todoman pkg,
│                               #   config.py, dir activation, pair contribution
└── parts/
    ├── vdirsyncer-pair.nix     # [pair tasks] fragment (item_types = ["VTODO"])
    └── todoman-config.nix      # ~/.config/todoman/config.py text
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
   instead of bare `https://caldav.icloud.com/`.
5. `vdirsyncer sync tasks`, then
   `find ~/.local/share/vdirsyncer/tasks -name '*.ics' | xargs grep -l VTODO`.
6. Round-trip: `todo new -l <list> "vdir test from laptop"` → `vdirsyncer sync
   tasks` → confirm it appears in Apple Reminders on the phone; add a reminder on
   the phone → sync → `todo list`.
7. CATEGORIES check (feeds Phase B `tasq` model mapping): confirm a
   `+project`/category survives the round-trip into Reminders. Record the result
   below — it decides whether Phase B encodes project/context via `CATEGORIES` or
   inline in the summary.
8. If `default_list` (`hwc.mail.tasks.defaultList`) doesn't match the discovered
   collection directory name, correct it and re-run `hms`.

**GO** only if discover lists a VTODO collection AND todoman→Reminders AND
Reminders→local all work.

### Go/no-go result
- (to be filled in after running on the laptop)
- CATEGORIES round-trip: _unknown_

## Changelog
- 2026-06-11: Initial Phase A — vdirsyncer VTODO pair (contributed to the shared
  calendar config/timer) + todoman CLI and config. TUI (`tasq`) deferred to Phase B.
