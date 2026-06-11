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
└── theme.tcss      # gruvbox dark
```

## Keymap
| Key       | Action                                                |
|-----------|-------------------------------------------------------|
| `a` / `e` | add / edit task (one-line todo.txt dialect, below)    |
| `x`/space | toggle done (reopen clears COMPLETED)                 |
| `d`       | delete (y/n confirm)                                  |
| `p`       | cycle priority none → A → B → C → none                |
| `/` `+` `@` | filter: grep summary / project / context (empty clears) |
| `esc`     | clear all filters                                     |
| `s`       | cycle sort: priority → due → created                  |
| `c`       | show/hide completed                                   |
| `l` / `L` | next / previous list (All → Reminders → Family)       |
| `j`/`k` `g`/`G` | cursor move / top / bottom                      |
| `r`       | reload from disk (after a sync pulled phone changes)  |
| `R`       | run `vdirsyncer sync tasks` in a worker, then reload  |
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
| `TASQ_PATH`  | `~/.local/share/vdirsyncer/tasks/*`           | glob of vdir list dirs |
| `TASQ_CACHE` | `~/.cache/tasq/cache.sqlite3`                 | tasq's own cache — deliberately separate from todoman CLI's (`~/.cache/todoman/`); sharing would collide on integer todo ids |

## Changelog
- 2026-06-11: Phase B initial. Textual TUI (textual 8.2.5) over todoman 4.7.0
  as a library (`toPythonModule pkgs.todoman` — no python3Packages.todoman
  exists). Verified end-to-end: pilot-tested add/edit/toggle/filter/delete,
  phone round-trip via vdirsyncer/iCloud. Enabled for the desktop role.
