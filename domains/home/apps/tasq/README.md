# tasq — VTODO-native keyboard task TUI

## Purpose
Fast Textual TUI over the tasks that sync to Apple Reminders (Phase A,
`domains/mail/tasks/`). Reads/writes standard VTODO `.ics` in the vdirsyncer
vdir; changes ride the existing 15-min `vdirsyncer.timer` (or `R` in-app) to
iCloud → Apple Reminders, and back. Stays byte-compatible with the `todo`
(todoman) CLI — both operate on the same vdir, tasq just keeps its own sqlite
cache.

## Boundaries
- Manages: the `tasq` runner (Python env: textual + icalendar + todoman-as-lib),
  `TASQ_PATH`/`TASQ_CACHE` env, `~/.cache/tasq/` creation.
- Does NOT manage: the vdir, vdirsyncer config/timer, or todoman's CLI config —
  all owned by `domains/mail/tasks/` + `domains/mail/calendar/`. Requires the
  Phase A backend to have synced at least once (else `tasq` exits with a hint).
- App source is git-tracked at `workspace/home/tasq/` and exec'd by absolute
  path (scraper precedent): editing `.py`/`.tcss` files is live, no rebuild;
  only `index.nix` / python-dep changes need `hms`.

## Structure
```
tasq/
└── index.nix       # Module: options hwc.home.apps.tasq.*, python env,
                    #   runner wrapper, cache-dir activation
workspace/home/tasq/   (git-tracked source, exec'd live)
├── app.py          # Textual App: bindings, actions, sync worker
├── store.py        # Hexagonal port over todoman.model.Database (ALL vdir I/O)
├── model_map.py    # "text +proj @ctx (A) due:YYYY-MM-DD" ↔ Todo fields
├── widgets.py      # ListSidebar, TaskTable, StatusBar, modals, help
├── theme.tcss      # gruvbox dark
└── WALKTHROUGH.md  # user guide: keymap, task-line dialect, usage examples
```

## Keymap
| Key       | Action                                                |
|-----------|-------------------------------------------------------|
| `a` / `e` | add / edit task (one-line dialect, below; `list:`/`due:` tokens) |
| `x`       | toggle done (reopen clears COMPLETED)                 |
| `d`       | delete task (y/n confirm)                             |
| `p`       | cycle priority none → A → B → C → none                |
| `space`   | leader — acts on the **selected task** (which-key menu): |
| `space l` | &nbsp;&nbsp;move it to a list (numbered, live)        |
| `space p` | &nbsp;&nbsp;set its +project (number · `n` new · `x` clear) |
| `space c` | &nbsp;&nbsp;set its @context (number · `n` new · `x` clear) |
| `space d` | &nbsp;&nbsp;edit its due date (today · tomorrow · mon–sun · ISO · empty clears) |
| `L`       | lists: `n` new · pick → `r` rename / `d` **DELETE** (CalDAV DELETE to Radicale — removes list + tasks from server and phone) |
| `P` / `C` | projects / contexts: pick → `r` rename everywhere / `d` remove from all tasks |
| `N`       | new list (shortcut for `L n`)                         |
| `/` `+` `@` | filter: grep summary / project / context (empty clears) |
| `esc`     | clear all filters                                     |
| `s`       | cycle sort: priority → due → created                  |
| `c`       | show/hide completed                                   |
| `ctrl+j` / `ctrl+k` | walk sidebar down/up and apply (aerc-style) |
| `[` / `]` | toggle sidebar / detail panel                         |
| Tab       | focus sidebar (LISTS/PROJECTS/CONTEXTS; Enter filters, re-select clears) |
| `j`/`k` `g`/`G` | cursor move / top / bottom                      |
| `w`       | toggle 7-day week strip (◆ khal events · ☐ tasks due · overdue in red) |
| `r`       | reload from disk (after a sync pulled phone changes)  |
| `R`       | sync (`vdirsyncer sync <pairs>`) in a worker, then reload |
| `K`       | suspend into `khal interactive` (calendar view)       |
| `?` / `q` | help / quit                                           |

## Task line dialect ↔ VTODO mapping
`"Buy lumber +shop @errand (A) due:2026-06-20"` →
- `SUMMARY:Buy lumber`
- `CATEGORIES:+shop,@errand` — sigils are **kept** in the category value; they
  round-trip through iCloud intact (verified Phase A) and read as tags in
  Apple Reminders.
- `PRIORITY:1` — `(A)`→1 (highest) … `(I)`→9, none→0 (todoman semantics).
- `DUE;VALUE=DATE:20260620` — `due:` accepts ISO dates, `today`, `tomorrow`.
  A datetime due renders/edits as its date (downgrades to all-day on edit).

## Env contract
| Var          | Default                                       | Meaning |
|--------------|-----------------------------------------------|---------|
| `TASQ_PATH`  | `~/.local/share/vdirsyncer/tasks/*`           | glob(s) of vdir list dirs, ":"-separated; the module appends the Radicale glob when `hwc.mail.tasks.radicale.enable` |
| `TASQ_CACHE` | `~/.cache/tasq/cache.sqlite3`                 | tasq's own cache — deliberately separate from todoman CLI's (`~/.cache/todoman/`); sharing would collide on integer todo ids |
| `TASQ_PALETTE` | (unset → hwc fallback)                      | JSON of `hwc.home.theme.colors`, exported by the module |
| `TASQ_SYNC_PAIRS` | `tasks`                                  | vdirsyncer pairs the `R` key syncs (`tasks tasks_radicale` with Radicale) |
| `TASQ_NEW_LIST_ROOT` / `TASQ_NEW_LIST_PAIR` | (unset)        | where `N` creates lists + the pair to discover/sync after; set to the Radicale storage when enabled — lists then genuinely sync |
| `TASQ_RADICALE_URL` / `TASQ_RADICALE_USER` / `TASQ_RADICALE_PW_CMD` | (unset) | Radicale CalDAV endpoint, user, and a shell command printing the password (mirrors the vdirsyncer pair). Set when Radicale is on; enable list deletion (`L` → `d`), which vdirsyncer can't do — a CalDAV DELETE removes the collection server-side |

## Changelog
- 2026-06-11: Phase B initial. Textual TUI (textual 8.2.5) over todoman 4.7.0
  as a library (`toPythonModule pkgs.todoman` — no python3Packages.todoman
  exists). Verified end-to-end: pilot-tested add/edit/toggle/filter/delete,
  phone round-trip via vdirsyncer/iCloud. Enabled for the desktop role.
- 2026-06-11: Added workspace/home/tasq/WALKTHROUGH.md — user-facing guide
  (keymap, task-line dialect, day-of-use examples, sync workflow).
- 2026-06-11: UI v2, tuxedo-style. Tomorrow-night palette, top header bar
  (list · count · sort · filters), sidebar reworked into LISTS / PROJECTS /
  CONTEXTS sections with live counts (select to filter, re-select to clear).
  New keys: `C` suspends into `khal interactive`; `N` creates a local-only
  list (sync pair is pinned to iCloud collection IDs — synced lists must be
  created in Apple Reminders and pinned in machines/laptop/home.nix).
- 2026-06-11: UI v3. Colors now come from the SYSTEM palette: the module
  exports hwc.home.theme.colors as TASQ_PALETTE (JSON); the app maps tokens
  to $tq-* Textual CSS variables — theme.tcss has zero hex literals, and
  switching hwc.home.theme.palette restyles tasq (hardcoded tuxedo palette
  reverted). Added tuxedo-style right DETAIL panel (priority/status/dates/
  list/projects/contexts/RAW/notes, follows the cursor). New keys: `J`/`K`
  walk-and-apply the sidebar from the table (aerc-style); `[`/`]` toggle
  sidebar/detail panes. Fixed: todoman cache returns last_modified as epoch
  float — detail panel converts before formatting.
- 2026-06-11: Week strip (`w`): 7-day grid across the bottom — khal events
  (◆, via `khal list --json`, recurrence expanded) merged with tasks due
  (☐, priority-colored), overdue tasks leading today's column in red;
  refreshes on r/R/sync. Radicale backend support: TASQ_PATH gains the
  tasks-radicale glob, R syncs both pairs, and `N` creates lists in the
  Radicale root + discover/sync pushes them server-side (genuinely synced
  lists). All driven off hwc.mail.tasks.radicale.enable — no tasq config.
- 2026-06-12: Week-strip overdue sort crash fixed (sorted() on (date, Todo)
  tuples fell through to Todo<Todo when due dates tied). `list:` token in the
  add/edit line targets (add) / moves (edit) a task to another list (ci, unique
  prefix). Store.move (db.move) + Store.rename_list (rewrites displayname).
- 2026-06-12: `space` is now a which-key leader acting on the selected task —
  `space l/p/c/d` move list / set +project / set @context / edit due. Due
  parsing gained weekday names (next occurrence) everywhere, incl. `due:`.
  Management on capitals: `L` lists, `P` projects, `C` contexts (pick → rename
  / delete). Rebindings: calendar `C`→`K`; sidebar step `J`/`K`→`ctrl+j/k`;
  `l` (cycle lists) dropped — `ctrl+j/k` is the way.
- 2026-06-12: Real list deletion (`L` → pick → `d`). vdirsyncer can't delete a
  collection (a removed local dir is re-pulled by the next `from a` discover),
  so tasq issues a CalDAV DELETE straight to Radicale — full control, the point
  of the Radicale migration. Removes the collection server-side (and from the
  phone), then the local dir + orphaned vdirsyncer status. Module injects
  TASQ_RADICALE_URL/USER/PW_CMD mirrored from the vdirsyncer pair + agenix
  htpasswd. Earlier "delete in Apple Reminders" advice was stale iCloud-era
  reasoning and is gone. Verified end-to-end against the live server with
  throwaway collections (MKCALENDAR→DELETE→404; real lists untouched).
