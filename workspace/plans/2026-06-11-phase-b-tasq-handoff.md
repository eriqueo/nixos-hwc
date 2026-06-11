# Phase B Handoff — Build `tasq`, a VTODO-native task TUI

> **How to use this file:** Paste everything below the `---` into a fresh Claude Code
> session opened in `~/.nixos` on `hwc-laptop`. It is self-contained: all context,
> verified facts, the exact module/packaging recipe, the app spec, and the
> definition of done. Phase A (the sync backend) is already DONE and live on `main` —
> this session only builds the TUI on top of it.

---

You are picking up **Phase B** of a task-manager project on Eric's NixOS config
(`~/.nixos`, Charter v12.1, machine `hwc-laptop`). Build a fully functional,
keyboard-driven terminal app called **`tasq`** (command: `tasq`) — a fast Textual
TUI over the tasks that already sync to Apple Reminders on Eric's phone. By the end,
`tasq` must launch, list/add/edit/complete/delete tasks, and have those changes
round-trip to the phone. Work to a real, working app — not a sketch.

## 0. Mission / Definition of Done

`tasq` is a NixOS Home Manager app that:
- Reads the existing VTODO vdir and renders a modern keyboard TUI (tuxedo-style keymap, calcurse-style layout).
- Creates / edits / completes / deletes tasks, writing standard VTODO `.ics` back to the vdir.
- Changes flow vdir → `vdirsyncer` (existing 15-min timer) → iCloud → Apple Reminders, and back.
- Is packaged as `domains/home/apps/tasq/`, enabled for the desktop role, boot-persistent after `sudo nixos-rebuild switch`.
- Stays byte-compatible with the `todo` (todoman) CLI — both operate on the same vdir.

**Done = the full Verification checklist (§9) passes, including a task created in `tasq` appearing in Apple Reminders on the phone and vice-versa.**

## 1. What already exists — Phase A (DONE, on `main`, do NOT rebuild it)

The sync backend is live and verified GO on hwc-laptop. Don't touch it; build on it.

- **vdir (source of truth):** `~/.local/share/vdirsyncer/tasks/<UID>/*.ics` — one dir per Reminders list, each with a `displayname` file. Currently **2 lists**: `36BB690C-…` = "Reminders" and `D788714B-…` = "Family". One VTODO per `.ics`.
- **Sync:** `vdirsyncer.timer` (systemd --user, every 15 min) syncs calendar + tasks together. Manual: `vdirsyncer sync tasks`. The tasks pair is pinned to the 2 VTODO collections (iCloud also exposes VEVENT calendars; do not re-add those).
- **todoman:** installed (`todo`), config at `~/.config/todoman/config.py` (`path = "~/.local/share/vdirsyncer/tasks/*"`, `default_list = "Reminders"`, `cache_path = "~/.cache/todoman/cache.sqlite3"`).
- **Phase A code on `main`:** `domains/mail/tasks/` (module), `domains/mail/calendar/{index,parts/vdirsyncer}.nix` (the `extraVdirsyncerPairs` hook), `machines/laptop/home.nix` (`hwc.mail.tasks` enable + pinned `collections`), `profiles/mail/home.nix`. Read `domains/mail/tasks/README.md` for the full backend story and the go/no-go results.

**Verified live:** `todo list` shows a real reminder ("Ryan's bday"); creating via `todo new` + `vdirsyncer sync tasks` lands it in Apple Reminders.

## 2. Verified facts — DO NOT re-derive these (they were tested this session)

### 2a. Packaging — the critical one
`todoman` is **NOT** an importable Python library in nixpkgs (`python3Packages.todoman`
does not exist — only the top-level `pkgs.todoman` application). The working recipe to
get `todoman.model` + `textual` + `icalendar` importable in one env is **verified**:

```nix
pythonEnv = pkgs.python3.withPackages (ps: [
  ps.textual                      # 8.2.5 in the pin
  ps.icalendar                    # 6.3.2 in the pin
  (ps.toPythonModule pkgs.todoman)   # 4.7.0 — toPythonModule exposes the lib
]);
```
Tested: `${pythonEnv}/bin/python -c "import todoman.model, textual, icalendar"` → OK
(todoman 4.7.0, textual 8.2.5). Use this exact recipe. The `toPythonModule` wrapper is
the whole trick — without it `ps.todoman` fails.

### 2b. `todoman.model` API (read in full from todoman 4.7.0 `model.py`; build the app on this)
- `Database(paths: Iterable[str], cache_path: str)` — `paths` = list of **vdir list-dirs** (each dir = one list); rescans on construction, so re-instantiating picks up vdirsyncer pulls. Uses a sqlite cache at `cache_path`.
- `db.todos(**kw) -> Iterator[Todo]` — kw: `lists`, `categories`, `priority`, `grep`, `sort`, `reverse`, `due`, `start`, `startable`, `status` (default `"NEEDS-ACTION,IN-PROCESS"`; pass `status=["ANY"]` for everything incl. completed).
- `db.todo(id) -> Todo` (int id). `db.lists() -> Iterator[TodoList]` (`.name`, `.path`, `.colour`).
- `db.save(todo)` — **the write path** (VtodoWriter; bumps sequence + last_modified; updates cache; atomic temp+rename). `db.delete(todo)`. `db.move(todo, new_list, from_list)`. `db.flush()` (purge completed).
- `Todo` fields: `summary, description, location` (str); `priority` (int, **1 = highest … 9, 0 = none**), `percent_complete`, `sequence`; `categories` (list[str] — the `+project/@context` carrier); `due, start, completed_at, created_at, last_modified` (datetime/date); `status` ∈ {NEEDS-ACTION, IN-PROCESS, COMPLETED, CANCELLED}; `uid, filename, rrule`. Methods `.complete()`, `.cancel()`, `.clone()`; props `.is_completed`, `.is_recurring`.
- **Create:** `t = Todo(new=True, list=<TodoList>)`; set fields; `db.save(t)` → writes `<uid>.ics`.
- **Caches:** use a **SEPARATE** cache from todoman's CLI → `~/.cache/tasq/cache.sqlite3` (both rebuild from the same vdir, so data is identical; separate files avoid integer-id collisions). Re-open the `Database` on a reload key to absorb external changes. Read-real path if you need to re-verify the API: it's in the nix store — `python3 -c "import todoman, os; print(os.path.dirname(todoman.__file__))"` then read `model.py`.

### 2c. Field-mapping decision is SETTLED
`CATEGORIES` and `PRIORITY` **survive the iCloud round-trip** (tested: a VTODO with
`CATEGORIES:work,urgent` + `PRIORITY:1` came back intact from iCloud). So map
`+project` / `@context` → `Todo.categories` (do **not** fall back to encoding them
inline in the summary). Apple Reminders shows categories as tags.

### 2d. Source-path / dev-loop mechanism (from the `domains/home/apps/scraper` precedent)
The app source lives **git-tracked in `workspace/home/tasq/`** and the module's runner
`exec`s it by absolute path — so **editing a `.py` takes effect immediately, no rebuild**
(only changing the Python env / module needs a rebuild). The repo path is resolved with
the standalone-safe handshake:
```nix
nixosPath = lib.attrByPath [ "hwc" "paths" "nixos" ] "/home/eric/.nixos" osConfig;
runner = pkgs.writeShellScriptBin "tasq" ''
  exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/tasq/app.py "$@"
'';
```
Running `python /abs/dir/app.py` puts `/abs/dir` on `sys.path[0]`, so `app.py` can
`import store, model_map, widgets` as siblings, and Textual `CSS_PATH = "theme.tcss"`
resolves next to the app module.

## 3. Files to create

```
domains/home/apps/tasq/
  index.nix          # NEW module (see §5 for the skeleton)
  README.md          # NEW (Law 12) — mirror domains/home/apps/tuxedo/README.md shape:
                     #   purpose, keymap table, the +proj/@ctx↔categories mapping, env contract
workspace/home/tasq/
  app.py             # Textual App: BINDINGS, screens, wires Store → widgets
  store.py           # thin wrapper over todoman.model.Database (see §4)
  model_map.py       # parse/render "text +proj @ctx (A) due:YYYY-MM-DD" ↔ Todo fields
  widgets.py         # TaskTable (DataTable), ListSidebar, FilterBar, Add/Edit + Confirm modals
  theme.tcss         # Textual CSS (gruvbox-ish, match the khal palette in machines/laptop)
```
Plus enable it (§6) and update `domains/home/apps/README.md` (add the `tasq` row, Law 12).

## 4. `store.py` — the backend wrapper (the hexagonal port)

Centralize ALL todoman.model use here so the UI never touches the vdir directly:
```
class Store:
    def __init__(self, glob_paths: list[str], cache_path: str): ...   # build Database
    def reload(self): ...                 # re-instantiate Database (absorbs vdirsyncer pulls)
    def lists(self) -> list[TodoList]: ...
    def todos(self, *, list=None, categories=None, grep=None, sort=None,
              show_completed=False) -> list[Todo]: ...
    def add(self, summary, *, list, categories=(), priority=0, due=None, description=""): ...
    def edit(self, todo, **fields): ...   # set fields → db.save(todo)
    def toggle_done(self, todo): ...      # .complete()/reopen → db.save
    def delete(self, todo): ...
    def sync(self) -> tuple[int,str]: ... # subprocess ["vdirsyncer","sync","tasks"] (call from a Textual @work worker, never the UI thread)
```
Resolve `glob_paths` from the env (see §6 — `TASQ_PATH` expands to the list dirs) or by
globbing `~/.local/share/vdirsyncer/tasks/*`. List display name = the dir's `displayname`
file (todoman's TodoList already exposes `.name`).

## 5. `index.nix` skeleton (Charter v12.1: namespace = folder → `hwc.home.apps.tasq.*`)

```nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.tasq;
  nixosPath = lib.attrByPath [ "hwc" "paths" "nixos" ] "/home/eric/.nixos" osConfig;
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.textual ps.icalendar (ps.toPythonModule pkgs.todoman)
  ]);
  runner = pkgs.writeShellScriptBin "tasq" ''
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/tasq/app.py "$@"
  '';
in {
  # OPTIONS  (inline — no separate options.nix)
  options.hwc.home.apps.tasq = {
    enable = lib.mkEnableOption "tasq — VTODO-native keyboard task TUI";
    tasksGlob = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/vdirsyncer/tasks/*";
      description = "Glob to the VTODO vdir list dirs (matches the Phase A tasks sync).";
    };
    cachePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/tasq/cache.sqlite3";
      description = "tasq's own todoman.model sqlite cache (separate from the todoman CLI's).";
    };
  };
  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    home.packages = [ runner ];
    home.sessionVariables = { TASQ_PATH = cfg.tasksGlob; TASQ_CACHE = cfg.cachePath; };
    home.activation.tasqDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.cache/tasq"}
    '';
    # VALIDATION
    assertions = [{
      assertion = builtins.pathExists (nixosPath + "/workspace/home/tasq/app.py");
      message = "hwc.home.apps.tasq: workspace/home/tasq/app.py is missing.";
    }];
  };
}
```
(`domains/home/apps/index.nix` auto-imports any subdir with an `index.nix` — no wiring needed.)

## 6. Enable site

Enable for the **desktop role** so it follows the laptop (which has roles `[base desktop]`):
in `profiles/desktop/home.nix`, add to the existing `hwc.home.apps` block:
`tasq.enable = lib.mkDefault true;`
(`tasq` has no machine-specific config — it reads the vdir the Phase A backend provides —
so it belongs at the role level, not the machine one-off.)

## 7. App spec (MVP)

**Layout (calcurse-inspired):** left **ListSidebar** (Reminders, Family) · main
**TaskTable** (`DataTable`: status ☐/☑, priority, summary, due, categories) · bottom
**FilterBar / command line**.

**Keymap (tuxedo-inspired Textual `BINDINGS`):**
`a` add · `x`/`space` toggle done · `e` edit · `d` delete (confirm modal) · `p` cycle
priority · `/` grep filter (summary) · `+`/`@` filter by project/context (→
`todos(categories=…)`) · `s` cycle sort (priority/due/created) · `l`/`L` next/prev list ·
`r` reload (re-open Database — picks up phone changes after sync) · `R` run `vdirsyncer
sync tasks` in a worker + toast · `g`/`G` top/bottom · `?` help · `q` quit.

**Add/Edit input (`model_map.py`):** a single line in todo.txt dialect →
`"Buy lumber +shop @errand (A) due:2026-06-20"` parses to `summary="Buy lumber"`,
`categories=["+shop","@errand"]` (keep the sigils so they round-trip and read well in
Reminders), `priority=1`, `due=2026-06-20`. Render Todos back to the same one-line form.
Priority map: `(A)`→1, `(B)`→2 … clamp to todoman's 1–9; none→0.

**Write-back:** every mutation → `Store` → `db.save()` → `.ics` in the list dir → next
`vdirsyncer sync` (timer or `R`) → iCloud → phone. No new serializer; reuse todoman's.

## 8. Dev loop (fast)

1. Build the env + module **once**: `hms` (alias for the standalone HM activation;
   if `hms` isn't a function in your shell, run:
   `nix build --no-link --print-out-paths '/home/eric/.nixos#homeConfigurations."eric@hwc-laptop".activationPackage' 2>/dev/null` then `"<path>/activate"`).
2. After that, **edit `workspace/home/tasq/*.py` and just run `tasq`** — the runner execs
   the live source, no rebuild needed. Only re-run `hms` when you change `index.nix` or add
   a Python dependency.
3. Final boot-persistence: `sudo nixos-rebuild switch --flake .#hwc-laptop` (system/mixed,
   because `profiles/desktop` is in the system lane). Commit before rebuilding.

## 9. Verification (this IS the definition of done — run all)

1. `${pythonEnv}/bin/python -c "import todoman.model, textual, icalendar"` → OK (packaging gate).
2. `tasq` launches; ListSidebar shows **Reminders** + **Family**; TaskTable shows the real
   reminder ("Ryan's bday").
3. In `tasq`: add `Test +shop @errand (A) due:2026-06-20`. Confirm a new `.ics` under
   `~/.local/share/vdirsyncer/tasks/36BB690C-…/` with `SUMMARY`, `CATEGORIES`, `PRIORITY`,
   `DUE` correct (`rg` the file).
4. `vdirsyncer sync tasks` (or press `R`) → the task appears in **Apple Reminders on the
   phone** with its tags. **Ask Eric to confirm on his phone.**
5. Add a reminder **on the phone** → `vdirsyncer sync tasks` → press `r` in `tasq` → it
   shows up. Complete it in `tasq` (`x`) → save → sync → shows completed on the phone.
6. `todo list` (todoman CLI) shows the same tasks `tasq` does (byte-compat proof).
7. **Clean up any test tasks you created** (delete in `tasq` → sync) so Eric's Reminders
   isn't littered.

## 10. Conventions & gotchas (carry these)

- **Charter v12.1:** namespace = folder; options inline in `index.nix` under `# OPTIONS`;
  implementation under `config = lib.mkIf cfg.enable`; assertions **inside** that block.
- **Law 12 READMEs:** create `domains/home/apps/tasq/README.md`; add a `tasq` row to
  `domains/home/apps/README.md`. Mirror `domains/home/apps/tuxedo/README.md` for shape.
- **Don't block the UI thread:** run `vdirsyncer sync` and any heavy `Database` rebuild in
  Textual `@work` workers; show a toast.
- **Separate sqlite cache** (`~/.cache/tasq/…`) from todoman's — never share the file.
- **Reload after external change:** re-instantiate the `Database` (the `r` key) to see
  phone-side edits after a sync; todoman's cache self-heals on construction.
- **One VTODO per `.ics`**, atomic writes (todoman handles this) — safe alongside vdirsyncer.
- **Git workflow (keep `main` clean — this is how Phase A was landed):** work on a short-lived
  branch (e.g. `feature/tasq`), commit incrementally, verify, then fast-forward/merge to
  `main` and delete the branch. Commit **before** any `nixos-rebuild`. **Eric sometimes runs
  parallel Claude sessions on this same repo** — commits from another session can land on your
  working tree (it happened during Phase A). Check `git log` before pushing, push with
  `--force-with-lease`, and don't sweep up unrelated commits.
- **HM dual-path:** HM-only edits → `hms`; the final boot-persistent activation needs
  `sudo nixos-rebuild switch` because the enable lives in `profiles/desktop` (system lane).

## 11. Read these first (in order)

1. `domains/mail/tasks/README.md` — the Phase A backend + verified go/no-go results.
2. `domains/home/apps/scraper/index.nix` — the python-app packaging precedent (runner + `nixosPath`).
3. `domains/home/apps/tuxedo/` — home-app module + README shape; tuxedo's `--help` shows the
   todo.txt command/keymap vocabulary worth echoing in `tasq`.
4. `CHARTER.md` + `domains/home/apps/index.nix` (auto-import) — module rules.
5. todoman `model.py` in the nix store (path via §2b) — the API you're building on.

Build it, verify end-to-end (§9) including the phone round-trip, clean up test data, then
report the result and open the PR.
