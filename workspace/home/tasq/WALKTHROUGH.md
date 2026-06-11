# tasq — Walkthrough

`tasq` is a keyboard-driven TUI over the same tasks you see in Apple Reminders
on your phone. Everything you do in it writes standard VTODO `.ics` files into
the vdirsyncer vdir; the 15-minute sync timer (or `R` in-app) carries changes
to iCloud and back. The `todo` CLI works on the exact same files.

## Launching

```
tasq
```

The screen has three areas:

```
┌──────────┬──────────────────────────────────────────────────┐
│ All      │   P  Summary                Due        Tags  List │
│ Family   │ ☐ A  Order hinges           2026-06-13 +shop ...  │
│ Reminders│ ☐    Ryan's bday            2024-09-24            │
│          │                                                   │
│ sidebar  │                 task table                        │
├──────────┴──────────────────────────────────────────────────┤
│ Reminders · sort:priority · showing:active · 2 tasks         │  ← status bar
│ a Add  e Edit  x Done  d Del  / Filter  s Sort  ...           │  ← key hints
└───────────────────────────────────────────────────────────────┘
```

The cursor starts in the task table. `j`/`k` (or arrows) move, `g`/`G` jump to
top/bottom. `?` shows the full keymap any time; `q` quits.

## The task line (used by add and edit)

One line describes the whole task:

```
summary words +project @context (A) due:YYYY-MM-DD
```

| Piece | Meaning | In Apple Reminders |
|---|---|---|
| plain words | the summary | title |
| `+name` | project tag → CATEGORIES | tag |
| `@name` | context tag → CATEGORIES | tag |
| `(A)`…`(I)` | priority 1 (highest) … 9 | priority flag |
| `due:2026-06-20` | due date (also `due:today`, `due:tomorrow`) | due date |

Everything except the summary is optional, and order doesn't matter.

## Walkthrough: a day of real use

### 1. Capture tasks — `a`

Press `a`, type the line, Enter:

```
Order soft-close hinges +hardware @shop (A) due:tomorrow
```

→ "Order soft-close hinges", tagged `+hardware` `@shop`, top priority, due
tomorrow. It lands in whichever list you're viewing (or **Reminders** when
viewing All).

More capture examples:

```
Call client about countertop reveal +jobsite-baxter (B)
Pick up dog food @errand
Sharpen planer blades +shop-maintenance due:2026-06-15
Sketch built-in layout for the Hendersons +design
```

Want it in **Family** instead? Press `l` until the status bar shows Family
(or click/Enter it in the sidebar), then `a`.

### 2. Work the list — `x`, `e`, `p`, `d`

- `x` (or space) — toggle the selected task done. Done tasks disappear from
  the active view; press `c` to show/hide completed ones. `x` on a completed
  task reopens it.
- `e` — edit. The task comes back as the same one-line form; change anything:

  ```
  Order soft-close hinges +hardware @shop (A) due:tomorrow
  →
  Order soft-close hinges and drawer slides +hardware @shop (B) due:2026-06-16
  ```

- `p` — cycle priority on the spot: none → (A) → (B) → (C) → none.
- `d` — delete, with a y/n confirm.

### 3. Narrow the view — `/`, `+`, `@`, `s`, `l`

- `/` — grep summaries. Type `hinge` → only tasks mentioning hinges.
- `+` — filter by project. Type `hardware` (sigil added for you) → only
  `+hardware` tasks.
- `@` — same for contexts: `@shop`, `@errand`…
- Empty input clears that filter; `esc` clears all filters at once.
- `s` — cycle sort: **priority** (A first) → **due** (soonest first) →
  **created** (newest first). Completed tasks always sink to the bottom.
- `l` / `L` — cycle lists: All → Family → Reminders. The status bar always
  shows where you are.

Example: heading to town? `@` then `errand` — that's your errand run, sorted
by priority.

### 4. Sync with the phone — `R` and `r`

Two directions, two keys:

- **`R` — push/pull now.** Runs `vdirsyncer sync tasks` in the background and
  reloads. Use after a capture session so tasks hit your phone before you
  leave the shop. (Otherwise the timer does it within 15 minutes anyway.)
- **`r` — reload from disk.** Cheap, local. Use when a sync already happened
  (timer, or you ran it elsewhere) and you want tasq to pick up phone-side
  changes.

Typical phone round-trip: add a reminder on the phone → wait for the timer
(or press `R`) → press `r` → it's in the table. Complete it with `x` → `R` →
it shows completed on the phone.

## Full keymap

| Key | Action |
|---|---|
| `a` / `e` | add / edit task (one-line form) |
| `x` / space | toggle done |
| `d` | delete (y/n confirm) |
| `p` | cycle priority none → A → B → C → none |
| `/` | filter: grep summary (empty clears) |
| `+` / `@` | filter: project / context (empty clears) |
| `esc` | clear all filters |
| `s` | cycle sort: priority → due → created |
| `c` | show/hide completed |
| `l` / `L` | next / previous list |
| `j` `k` / `g` `G` | move cursor / jump top, bottom |
| `r` | reload from disk |
| `R` | sync with iCloud now, then reload |
| `?` | help |
| `q` | quit |

## Good to know

- **The `todo` CLI is interchangeable.** `todo list`, `todo new` etc. operate
  on the same files; use whichever is at hand.
- **Tags keep their sigils** (`+shop`, `@errand`) so they read the same in
  Reminders and survive the round-trip.
- **Recurring tasks** (like a yearly birthday): completing one automatically
  creates the next occurrence.
- **Editing a task that has a due *time*** keeps only the date (tasq's dialect
  is all-day).
- **Overdue dues show red, today shows yellow** in the table.
- The app source is live at `~/.nixos/workspace/home/tasq/` — tweaks to the
  Python or theme take effect on next launch, no rebuild.
