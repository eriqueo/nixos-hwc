# tasq — Walkthrough

`tasq` is a keyboard-driven TUI over the same tasks you see in Apple Reminders
on your phone. Everything you do in it writes standard VTODO `.ics` files into
the vdirsyncer vdir; the 15-minute sync timer (or `R` in-app) carries changes
to iCloud and back. The `todo` CLI works on the exact same files.

## Launching

```
tasq
```

```
  tasq · Reminders · 5 tasks · sort:priority                   ← header bar
┌──────────────┬─────────────────────────────────┬─────────────┐
│ LISTS        │   P  Summary           Due  Tags│ DETAIL      │
│  All       5 │ ☐ A  Order hinges      06-13 +sh│ priority (A)│
│  Family    0 │ ☐    Ryan's bday       09-24    │ status   …  │
│  Reminders 5 │                                 │ due      …  │
│              │                                 │ created  …  │
│ PROJECTS     │                                 │ list     …  │
│  +hwc      1 │                                 │ projects …  │
│  +finance  1 │                                 │ contexts …  │
│              │                                 │             │
│ CONTEXTS     │                                 │ RAW         │
│  @errand   1 │                                 │ Order hinges│
│  @shop     1 │                                 │ +hardware … │
├──────────────┴─────────────────────────────────┴─────────────┤
│ a Add  e Edit  x Done  d Del  / Filter  s Sort  C Cal  ...    │
└───────────────────────────────────────────────────────────────┘
```

The cursor starts in the task table. `j`/`k` (or arrows) move, `g`/`G` jump to
top/bottom. The right DETAIL panel always shows the selected task in full.
`[` hides the sidebar, `]` hides the detail panel (more room for the table).
`Tab` moves focus to the sidebar (Enter selects) — or stay in the table and
drive the sidebar with `J`/`K` (aerc-style: each press moves the sidebar
selection and applies it). `?` shows the full keymap any time, `q` quits.

Colors come from the system theme (`hwc.home.theme.palette`) — tasq reads the
materialized palette, so switching the system palette restyles it.

## The sidebar: lists, projects, contexts

Three sections, each with live task counts:

- **LISTS** — your Apple Reminders lists (Reminders, Family). These are real
  containers: a task lives in exactly one list, and lists sync to the phone.
  Select one (or All) to scope the table; `l`/`L` cycle without leaving the
  table.
- **PROJECTS** (`+name`) — *what outcome is this task part of?* A project is
  a multi-task goal: `+baxter-kitchen`, `+hwc-website`, `+shop-buildout`.
  When it's finished, the tag retires.
- **CONTEXTS** (`@name`) — *where/when/with-what can I do this?* A context is
  a situation, and it never finishes: `@shop`, `@errand`, `@phone`,
  `@computer`, `@home`.

The split is from GTD: projects answer "what am I trying to move forward?"
(planning view), contexts answer "what can I do right now, given where I am?"
(doing view). `Call the glass supplier +baxter-kitchen @phone` shows up both
when you review the Baxter job and when you're knocking out phone calls.

Selecting a project or context filters the table; selecting it again (or
`esc`) clears the filter. Both are stored as VTODO `CATEGORIES`, so they show
up as tags on the phone.

## The task line (used by add and edit)

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
Call client about countertop reveal +jobsite-baxter @phone (B)
Pick up dog food @errand
Sharpen planer blades +shop-maintenance due:2026-06-15
```

Tasks land in whichever list you're viewing (**Reminders** when viewing All).
Want one in **Family**? Press `l` until the header shows Family, then `a`.

### 2. Work the list — `x`, `e`, `p`, `d`

- `x` (or space) — toggle the selected task done. Done tasks disappear from
  the active view; `c` shows/hides completed. `x` on a completed task reopens it.
- `e` — edit: the task comes back as its one-line form; change anything.
- `p` — cycle priority in place: none → (A) → (B) → (C) → none.
- `d` — delete, with a y/n confirm.

### 3. Narrow the view

- Select a project/context in the sidebar — or `+` / `@` to type one.
- `/` — grep summaries (`hinge` → only hinge tasks).
- Empty input clears that filter; `esc` clears everything.
- `s` — cycle sort: **priority** → **due** → **created**. Completed sink.
- Heading to town? Select `@errand` in the sidebar — that's your errand run.

### 4. See it on a calendar — `C`

`C` suspends tasq and opens **khal interactive** — your iCloud calendars plus
dated items in month view. Quit khal (`q`) and you're back in tasq exactly
where you were.

### 5. Sync with the phone — `R` and `r`

- **`R` — push/pull now.** Runs `vdirsyncer sync tasks` in the background and
  reloads. Use after a capture session so tasks hit your phone before you
  leave the shop. (The timer does it within 15 minutes anyway.)
- **`r` — reload from disk.** Cheap, local. Use when a sync already happened
  and you want tasq to pick up phone-side changes.

Phone round-trip: add a reminder on the phone → `R` (or wait) → `r` → it's in
the table. Complete it with `x` → `R` → completed on the phone.

## Adding lists — `N` (read this first)

`N` prompts for a name and creates a new **local** list (a new vdir
collection). tasq and the `todo` CLI can use it immediately — but it will
**never reach the phone**: the sync pair is pinned to the iCloud collection
IDs in `machines/laptop/home.nix`, and iCloud is the authority on which
Reminders lists exist.

To add a **phone-synced** list:

1. Create the list in Apple Reminders (Add List).
2. Find its collection ID:
   `vdirsyncer discover tasks` (it prints all collections; the new UID is the
   unfamiliar one — confirm VTODO support per `domains/mail/tasks/README.md`).
3. Add the ID to `hwc.mail.tasks.collections` in
   `~/.nixos/machines/laptop/home.nix`, commit, run `hms`.
4. `vdirsyncer discover tasks` then `vdirsyncer sync tasks` → press `r`.

Use `N` for scratch/local-only lists; use the phone for lists that matter.

## Full keymap

| Key | Action |
|---|---|
| `a` / `e` | add / edit task (one-line form) |
| `x` / space | toggle done |
| `d` | delete (y/n confirm) |
| `p` | cycle priority none → A → B → C → none |
| `N` | new list (local-only — see above) |
| `/` | filter: grep summary (empty clears) |
| `+` / `@` | filter: project / context (empty clears) |
| `esc` | clear all filters |
| `s` | cycle sort: priority → due → created |
| `c` | show/hide completed |
| `l` / `L` | next / previous list |
| `J` / `K` | walk the sidebar down/up and apply (lists → projects → contexts) |
| `[` / `]` | toggle sidebar / detail panel |
| `Tab` | focus sidebar (Enter selects; re-select clears a filter) |
| `j` `k` / `g` `G` | move cursor / jump top, bottom |
| `r` | reload from disk |
| `R` | sync with iCloud now, then reload |
| `C` | open khal interactive (calendar view) |
| `?` / `q` | help / quit |

## Good to know

- **The `todo` CLI is interchangeable.** Same files, either tool.
- **Tags keep their sigils** (`+shop`, `@errand`) so they read the same in
  Reminders and survive the round-trip. Tags created on the phone without a
  sigil appear in a separate TAGS sidebar section.
- **Recurring tasks** (like a yearly birthday): completing one automatically
  creates the next occurrence.
- **Editing a task that has a due *time*** keeps only the date.
- **Overdue dues show red, today shows yellow.**
- The app source is live at `~/.nixos/workspace/home/tasq/` — tweaks to the
  Python or theme take effect on next launch, no rebuild.
