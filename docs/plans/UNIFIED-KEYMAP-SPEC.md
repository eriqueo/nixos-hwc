# Unified Workbench Keymap — Plain-Language Design Spec (v0)

**Status:** proposed, not reviewed. Nothing committed.
**Branch:** `feat/workbench-zellij`. **Apply path:** Home-Manager only (`hms`), never `nixos-rebuild`.

## The one-sentence idea

Right now every TUI app invents its own keys by hand, so they drift apart. We're going to
**write the keys down once, in one Nix file, and have that file generate the key config for
every app** — the same way `hwc.home.theme` already generates colours for every app. Change one
line, every app re-keys.

There are two kinds of keys, and they must not fight:

- **"Do something inside this app" keys** → start with **Space**. Same grammar in every app.
- **"Jump to a different app" keys** → start with **Alt+Space**. These live in zellij (the pane
  manager), not in any app.

Why split them: when you're typing in todui, todui owns the keyboard. Space is *todui's* leader.
The host app sitting next to it can't grab keys out of todui's pane. So "jump between apps" has
to be handled one level up, by zellij, with a different starting key.

---

## Part 1 — What exists today (inventory)

| App | What starts a command | Can it do multi-key combos? | Where the keys are defined today |
|-----|----|----|----|
| **yazi** (files) | Space | Yes | hand-written in `yazi/parts/keymap.nix` |
| **nvim** (editor) | Space | Yes | hand-written lua |
| **aerc** (mail) | Space | Yes | half hand-written, half auto-generated from `tags.nix` |
| **khalt** (calendar) | Space | Only as pop-up menus (press Space, a menu appears, pick one key, maybe another menu) | leaf keys in `khal.spec`; the menu shape is hard-coded in the fork's Python |
| **todui** (tasks) | Space, but mostly bare single keys | Only as pop-up menus | hard-coded in Python, **no way to change keys from config** |
| **workbench host** | Space | Yes (real combos) | grammar hard-coded; app list comes from TOML files |
| **zellij** (pane manager) | nothing set | — | **nothing defined → it silently uses its factory defaults** |

---

## Part 2 — The conflicts, spelled out

These are the actual problems, described as "what happens when you press a key."

### Conflict 0 — "Jump to mail" only works from one pane (the big one)

**What happens today:** the workbench host pane is where `Space t` / `Space c` / `Space m`
(go to tasks / calendar / mail) are wired. Those keys only do anything **while the host pane is
the focused one.** The moment you click into the todui pane to actually work, pressing `Space m`
does nothing useful for mail — Space now belongs to todui. So "jump to mail" is broken from
everywhere except the one pane you're least likely to be sitting in.

**Why:** keys typed into a pane are owned by that pane's app. The host literally cannot see them.

**Fix:** move all "jump between apps" keys out of the host and into **zellij**, under a different
starting key (**Alt+Space**), so they work no matter which pane you're in.

### Conflict 1 — zellij is silently stealing keys from your apps

**What happens today:** zellij has no key config, so it runs its **factory-default keys**, which
include `Ctrl+t`, `Ctrl+p`, `Ctrl+n`, `Ctrl+s`. zellij grabs those *before* the app in the pane
ever sees them. But aerc uses `Ctrl+t` (open terminal), `Ctrl+p`/`Ctrl+n` (switch account), and
both aerc and yazi use `Ctrl+s`. So in mail, `Ctrl+t` doesn't open a terminal — zellij eats it.

**Why:** "no config" doesn't mean "no keys." It means "all the defaults are on."

**Fix:** explicitly turn off the default zellij keys that collide, and only keep the one
Alt+Space jump key.

### Conflict 2 — the obvious jump key (Ctrl+Space) is already taken

**What happens today:** in nvim, `Ctrl+Space` triggers autocomplete. So we can't use Ctrl+Space
as the "jump between apps" key — it'd break completion in the editor.

**Fix:** use **Alt+Space** instead (free in every app).

### Conflict 3 — the letter `s` means three different things

**What happens today**, same finger memory, three results:
- in yazi, `Space s` starts **sorting** (`Space s s` = sort by size)
- in aerc, `Space s` starts **sorting** too (`Space s d` = sort by date)
- in nvim, `Space s` is **session/search** (`Space s s` = save session)

So `Space s` is a coin toss depending on which pane you're in.

**Fix (DECIDED):** `s` = **sort** everywhere (matches yazi/aerc as-is — no change to those). All
the "look for something" verbs consolidate under **`f` = search** (find file, grep, filter). Only
nvim's `Space s` session keys move (to `Space m`, since sessions aren't sort). This is the
*lower-disruption* choice — yazi/aerc sort fingers are untouched.

### Conflict 4 — the letter `t` means four different things

- yazi: `Space t` = **tabs** (`Space t n` = new tab)
- nvim: `Space t` = a mix of **toggles and tabs**
- aerc: `Space t` = **toggle** (threads on/off)
- khalt: `t` = **jump to today** (not even a menu — a bare action)

**Fix:** `t` means **toggle** everywhere (hidden files, word-wrap, thread view…). **Tabs move to
`b`** (the buffers/tabs/lists group). "Today" in khalt becomes `Space g t` (go → today).

### Conflict 5 — todui mostly ignores the shared grammar

**What happens today:** in todui almost everything is a bare single key — `a` add, `e` edit,
`x` done, `d` delete, `s` sort, `c` show-completed, `w` week. That's fine and fast. The problem is
only its **Space menu** (`Space l/p/c/d` for assigning list/project/context/due) doesn't match the
shared groups, so the one place you'd look for a consistent menu is inconsistent.

**Fix:** keep todui's fast bare keys (don't slow you down), but make its **Space menu** follow the
shared map so it's discoverable like the others.

### Conflict 6 — `f` means "find files" in one app and "filter" in another

`Space f f` finds a file in nvim but filters the list in aerc/yazi. Close enough that it's
tolerable, but worth nailing down: `f` = **find** (files/items by name), and that's it.

### Conflict 7 — you can't always see the menu (which-key)

todui, khalt and the host pop up a little "which key does what" hint. yazi shows it on `?`.
**nvim shows nothing** (no which-key plugin). So the "press Space and the options appear" promise
is only half-true today.

**Fix:** add the which-key plugin to nvim; accept yazi/aerc using their static help screens.

---

## Part 3 — The new unified keymap

### 3.1 Jumping between apps — **Alt+Space**, handled by zellij

Press **Alt+Space**, then one letter. Works from any pane, any app:

| After Alt+Space | Goes to |
|---|---|
| `t` | tasks (todui) |
| `c` | calendar (khalt) |
| `m` | mail (aerc) |
| `f` | files (yazi) |
| `e` | edit (nvim) |
| `h` | host (workbench dashboard) |
| `n` / `p` | next / previous pane |
| `]` / `[` | next / previous tab |
| `w` pick a pane · `z` zoom · `d` detach · `q` quit session | |
| `Esc` | never mind |

**The mental rule:** *Space = do something here. Alt+Space = go somewhere else.*

### 3.1a Consistency is by *role*, not global

We do **not** force all six apps to share bare keys. Consistency applies within a role:

- **List apps (todui + khalt)** — a task and an event are both "an item in a list." These two
  share a bare verb set: **`a` add · `e` edit · `d` delete · `Enter` open/view.** This is the
  consistency that matters day-to-day.
- **Editor (nvim)** — keeps vim motions. Bare `e` (end-of-word) and `a` (append) are sacred;
  nvim's verbs live under `Space` / `Space m` instead.
- **Mail (aerc)** — keeps mail verbs (`c` compose, `r` reply).
- **Files (yazi)** — keeps file verbs (`dd`, `yy`, `r` rename).

The **Space grammar below is universal**; the **bare verbs above are role-scoped.** nvim being
different from todui/khalt is fine — nvim isn't a list app.

> **khalt remap needed:** khalt today uses `n`=new, `Enter`=edit, `e`=*export*. To match todui it
> becomes `a`=add, `e`=edit, and export moves to `Space m x`.

### 3.1b Two-column navigation rule (already consistent — now a standard)

Apps with a primary list and a secondary column use the **same keys, modifier picks the column**:

- **bare `j` / `k`** → move in the **primary** list (tasks, messages, files).
- **`Ctrl+j` / `Ctrl+k`** → move in the **secondary/side** column (todui: lists→projects→contexts;
  aerc: mail folders).

This is *already* how todui and aerc behave — we just make it the rule for any app with two
columns. **No conflict with zellij:** zellij's defaults never bind `Ctrl+j/k`, and our design strips
zellij's default keys and uses `Alt+Space`, so `Ctrl+j/k` passes straight to the focused app.
*Caveat:* telling `Ctrl+j` apart from Enter needs kitty's keyboard protocol on — verify live.

### 3.1c How you discover keys (helpers everywhere)

The whole point is to *learn* the system, so discovery is built in three ways:

1. **`Space` always pops a which-key map** in every app (nvim gets the which-key plugin it lacks
   today). For **nvim specifically, the helper also surfaces the baked-in vim keymaps**, not just
   our custom ones, so you can see the native commands too. *(Capability note: which-key shows
   registered mappings + our spec; a few pure built-in motions like `w`/`b`/`e` aren't in the
   table — we register/annotate what we can.)*
2. **Every bare key is also aliased under `Space`** — so when you forget a bare key, pressing
   `Space` is always a safe way to find it. Bare = fast; `Space` = the safety net to the same action.
3. **A minimal bare-key cheat-strip pinned at the bottom** of todui, khalt, yazi, and aerc (**not
   nvim** — nvim uses its which-key popup instead). Always-on reminder of the fast keys.

4. **`Alt+Space` opens a floating helper pane** (not just a status-bar hint). The floating popup is
   deliberate: a real centered popup for *between-apps* vs the in-app which-key makes the
   distinction visible — different surface = different layer.

### 3.2 Doing things inside an app — **Space**, same grammar everywhere

Press **Space**, then a group letter, then the action. The **meaning of each group letter is the
promise** — an app skips groups it doesn't need, but never repurposes a letter.

| Space → | Group | Means | Example |
|---|---|---|---|
| `g` | **go** | jump somewhere: folders, mailboxes, dates, top/bottom | `Space g h` = go home |
| `f` | **search** | look for something: find files, grep, filter | `Space f f` = find file · `Space f g` = grep |
| `s` | **sort** | sort the current list | `Space s s` = sort by size |
| `b` | **buffers/tabs/lists** | switch between open things (per app: nvim=buffers, yazi=tabs, todui=lists) | `Space b n` = next |
| `t` | **toggle** | flip a setting on/off | `Space t h` = toggle hidden |
| `y` | **yank** | copy path/name/text | `Space y p` = copy path |
| `d` | **delete** | remove | `Space d d` = delete |
| `w` | **window/view** | splits, view modes | `Space w v` = vertical split |
| `p` | **project** | project-wide actions | `Space p f` = project files |
| `o` | **open** | open/create external | `Space o v` = open file tree |
| `m` | **major mode** | *this app's special verbs* (see 3.3) | `Space m s` = sort |
| `q` | **quit/sync** | quit, reload, sync | `Space q r` = reload |

**Bare keys that stay exactly the same in every app** (these are vim movements, not commands, and
the factory does **not** touch them): `h j k l`, `gg` / `G`, `/`, `n` / `N`, `q`, `?`, `o` / `O`,
`r`, `i`.

### 3.3 `Space m` = "this app's own stuff" (where differences are parked)

Every app has verbs that don't generalise (sorting tasks vs sorting mail vs exporting a calendar
event). Instead of forcing them into shared letters and creating conflicts, they all live under
`Space m` ("major mode"), the app-specific drawer. **aerc already works exactly this way**
(`Space m` is its tag/label menu), so this isn't new — we're spreading a pattern that already
exists.

- **todui** `Space m`: priority, due, assign list/project/context — *add/edit/delete/done are bare
  keys (`a`/`e`/`d`/`x`), not here; sort is `Space s`*
- **khalt** `Space m`: duplicate, export, view-cycle (agenda/month/quarter) — *add/edit/delete are
  the shared bare list verbs `a`/`e`/`d`, not here*
- **yazi** `Space m`: change permissions, view modes — *sort is `Space s`*
- **nvim** `Space m`: LSP — rename, code-action, format, find references; sessions
- **aerc** `Space m`: tag/label the message (unchanged — already generated from `tags.nix`)

---

## Part 4 — What changes for *you*, app by app

This is the "how does my daily use change" part. **If a key isn't listed here, it doesn't change.**

### yazi (file manager)
- **Grep moves under search:** `Space /` → **`Space f g`** (`f` is the search group).
- **Tabs move:** `Space t n/c/1-4` → **`Space b n/c/1-4`** (tabs join the buffers group).
- **Unchanged:** **sort `Space s*` stays put** (you decided `s`=sort), all bare keys
  (`h j k l`, `dd`, `yy`, `gg`, `gh/gc/gn…` bookmarks), `Space y*` (copy), `Space w*` (view modes),
  `Space f` (filter, now clearly the search group).
- **Net:** two things move (grep label, tabs). Sort untouched.

### nvim (editor)
- **Sessions move:** `Space s s/l` → **`Space m`** (sessions aren't sort; `s` is now sort-only).
- **Toggle-wrap moves to toggles:** `Space s w` → **`Space t w`**.
- **Tabs move:** `Space t t/c/1-4` → **`Space b …`** (so `t` is purely toggles; buffers were
  already `Space b`, tabs now join them).
- **LSP actions move under the app menu:** `Space v rn/ca/f/rr` → **`Space m r/a/f/R`**.
- **Unchanged:** `Space f f` (find file) and `Space f g` (grep) — both already under `f`,
  bare LSP gotos (`gd gD gi gt`), all motions, window splits. Bare `a`/`e` stay vim (append /
  end-of-word) — nvim is the editor, not a list app.
- **New:** a which-key popup appears after Space (today nvim shows nothing) — and it's configured
  to **also surface nvim's baked-in keymaps**, so you can see native commands, not just ours.
  (nvim is the one app with **no** bottom cheat-strip — the popup is its discovery surface.)
- **Net:** sessions, toggle-wrap, tabs, and LSP actions relocate; find/grep/buffers stay put.

### aerc (mail) — least disruption
- **Search consolidates under `f`:** `Space f s` (search) and `Space f f` (filter) both stay
  under `f` — no move.
- **Unchanged:** **sort `Space s d` stays**, `Space g*` (jump to folder — all your category
  letters), `Space m*` (tag/label — your whole tagging system), `Space t t` (toggle threads),
  bare mail verbs (`c` compose, `r` reply).
- **Net:** aerc essentially doesn't change. It's already the model.

### khalt (calendar) — adopts the list-app verbs
- **Gets the shared list verbs:** `a` add (was `n`), `e` edit (was `Enter`), `d` delete (already),
  `Enter` open — so creating/editing an event uses the **same keys as todui**.
- **Export/duplicate/view-cycle move to the app menu:** `e` export → **`Space m x`**, duplicate →
  `Space m p`, agenda/month/quarter + `z` cycle → **`Space m`**.
- **"Today" becomes a go:** bare `t` → **`Space g t`**.
- **Reload:** `Space r` → **`Space q r`**.
- **Unchanged:** all bare calendar movement (`h j k l`, `[`/`]` month jump, arrows).
- **Caveat:** khalt's menu *structure* is hard-coded in its Python fork — adopting the list verbs
  and re-grouping needs `build_keymap()` taught to read the structure from injected config, or
  khalt ships a documented subset.

### todui (tasks) — fast keys stay fast, now shared with khalt
- **Bare verbs are the shared list-app set:** `a` add, `e` edit, `d` delete, `Enter` open — these
  now **match khalt exactly** (the consistency you asked for). Kept bare so they stay fast.
- **todui-only bare keys stay:** `x` done, `c` completed, `w` week, `s` sort, `r` reload, `R` sync,
  `j/k` move. (`s`=sort here too — consistent with the group meaning.)
- **The Space menu gets tidied:** `Space l/p/c/d` (assign list/project/context/due) is re-labelled
  to the shared map (`b`=lists, `p`=project…) and shown in a which-key popup.
- **Caveat:** todui's keys are hard-coded in Python with no config hook today. Even this needs
  todui to first read `TODUI_KEYMAP`. Until then it works as-is, just not centrally driven.

### workbench host (dashboard)
- **Loses the app-jump keys:** `Space t/c/m` (which only worked here anyway) go away — that job
  moves to **Alt+Space** so it works everywhere. The host's Space is now purely for the dashboard
  (cycle hubs, command palette).
- **Net:** you stop using the host as the "switchboard"; Alt+Space is the switchboard now.

### zellij (pane manager)
- **Stops stealing keys:** the default `Ctrl+t/p/n/s` that currently get eaten before reaching
  aerc/yazi are turned off. (`Ctrl+j/k` was never bound by zellij — the two-column nav is safe.)
- **Gains one job:** `Alt+Space` → opens a **floating helper pane** showing the jump map, which then
  takes the next key (`m` mail, `t` tasks, …) and moves you. The floating popup is what makes the
  in-app-vs-between-apps distinction visible.
- **Net:** the things that mysteriously didn't work in mail (`Ctrl+t` etc.) start working, and you
  get a real popup for jumping between apps.

---

## Part 5 — How the factory works (one file → all apps)

Mirror the theme exactly. Theme today: `hwc.home.theme.palette` (the data) → `colors` →
each app has a `parts/appearance.nix` that turns colours into that app's format. We add the same
shape for keys:

```
domains/home/keymap/
  index.nix     # defines hwc.home.keymap.* and wires the generators
  grammar.nix   # THE one file you edit — groups, shared keys, per-app menus, the jump menu
  parts/
    to-yazi.nix      # turns the data into yazi's keymap.toml text
    to-nvim.nix      # turns the data into nvim's lua (only the Space-menu layer)
    to-aerc.nix      # turns the data into aerc's binds.conf
    to-khalt.nix     # turns the data into khal's [keybindings]
    to-todui.nix     # turns the data into TODUI_KEYMAP (env var the app reads)
    to-workbench.nix # turns the data into WORKBENCH_KEYMAP (env var the app reads)
    to-zellij.nix    # turns the jump menu into zellij's keybinds
  README.md
```

The apps that already read a config file (yazi, nvim, aerc, khalt, zellij) get their text
generated at build time — **no change to the app itself.** The two apps with hard-coded keys
(todui, workbench) need to first learn to read a `*_KEYMAP` env var; until they do, they keep
their current keys and just aren't centrally driven yet.

**Order of work (lowest risk first):**
1. Build `grammar.nix` + the five build-time generators (yazi, nvim, aerc, khalt, zellij). These
   restyle immediately on `hms`, no app code changes.
2. Teach workbench to read `WORKBENCH_KEYMAP` and move the jump keys to zellij.
3. Teach todui to read `TODUI_KEYMAP` (biggest app change — do it last).

---

## Part 6 — What could go wrong (premortem)

1. **todui turns into a rewrite.** Its keys are 100% hard-coded. → Do it last; it keeps working
   meanwhile.
2. **We over-generate nvim** and lose the rich hand-written lua. → Generate *only* the Space-menu
   layer; leave movement, LSP-on-attach, and plugins as hand-written lua.
3. **khalt's menu won't bend** because the shape is Python. → Teach it to read the shape from
   config, or document it as a subset.
4. **Alt+Space is eaten** by Hyprland or the terminal. → It's a single Nix variable; test it live
   before committing; fall back to another key in one edit.
5. **Fast bare keys are invisible to the helper.** which-key only fires after Space, so bare
   `a/e/d` never show — the very keys you want help remembering. → todui/khalt show a persistent
   cheat-strip *and/or* alias the verbs under `Space m` (open decision #3 below).
6. **An app silently ignores the env var** and nothing changes, but it *looks* done. → The apps
   must print a warning when the keymap env var is missing, not fail quietly.
7. **aerc's tag system breaks** if we fold it into the central file. → The central file *composes*
   aerc's tag menu from `tags.nix`; it doesn't swallow it.
8. **Work lands on the wrong branch.** → Everything goes on `feat/workbench-zellij`.
9. **The two apps you most want consistent (todui, khalt) need the most app-side work** (todui
   hard-coded, khalt menu-tree forked). The consistency you care about lands *last*, after the
   build-time apps. → Accept the order, or front-load todui/khalt despite the higher cost.

---

## Decisions — all resolved

- **Groups:** `f`=search · `s`=sort · `b`=buffer/tab/list.
- **List-app verbs** (todui+khalt only): `a` add · `e` edit · `d` delete · `Enter` open. `x`=done
  stays todui-only; nothing else forced shared.
- **Leftovers** (nvim sessions, yazi chmod/view-modes, khalt duplicate/export/view-cycle, todui
  priority/due) all live under **`Space m`**.
- **Two-column nav:** bare `j/k` = primary list, `Ctrl+j/k` = side column (see 3.1b).
- **Discovery (see 3.1c):** Space pops which-key in every app; nvim's helper also shows baked-in
  vim keymaps; every bare key is also aliased under Space; a bottom cheat-strip is pinned in
  todui/khalt/yazi/aerc (not nvim); **Alt+Space opens a floating helper pane.**
- **Scope:** build *everything* — order is just internal risk management, not a gate.

**Remaining real-world checks (not decisions, verifications):**
- kitty keyboard protocol on, so `Ctrl+j` ≠ Enter (3.1b caveat).
- `Alt+Space` survives Hyprland/kitty before it reaches zellij.
- todui/khalt must *log* (not silently ignore) a missing `*_KEYMAP` so drift can't hide.
