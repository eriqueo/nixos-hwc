# inbox-janitor — Inbox Downloads Drainer

## Purpose

Keeps `~/000_inbox/downloads` (the OS download target — `~/Downloads` is a symlink
into it, Syncthing-shared laptop↔server) from re-accumulating. On a timer it reads
the declarative rule table `~/000_inbox/_inbox-routing.yaml` and routes each **loose
file at the root of `downloads/`** into a small set of **intrinsic-attribute buckets**:

- **agent** → `downloads/agent/` — Claude-Code / LLM output (`.md` and anything
  written to `downloads/agent/` directly by the convention below).
- **docs** → `downloads/docs/` — real documents you download (pdf, docx, txt).
- **data** → `downloads/data/` — csv, json, xlsx, sql…
- **code** → `downloads/code/` — ts, py, sh, zip/tar, html…
- **media** → `downloads/media/` — images, audio, video, fonts, design assets.
- **secrets** → `downloads/_secrets/` (quarantine; never renamed, never drained off-host).
- **unmatched** → `downloads/_review/` (fail-loud; a human/LLM routes by hand).

Organized bucket folders are never swept by the default drain, so the pass is
idempotent. A `--from`/`--all` re-run *does* walk them, and `run()` holds that
invariant there with an in-place guard: a file already sitting in its correct
bucket under its correct name is skipped. Without the guard `unique()` compares
the file against itself (`t.exists()` is true for its own path) and `rename_new`
"resolves" the collision by duplicating it to `foo_2.md` — then `foo_3.md` next
pass. The `*_2.*` files in `downloads/agent/` are that bug's artifacts.

## Why intrinsic attributes (the v2 rewrite)

v1 routed by **domain/class** (`datax/notes`, `business/admin`) — a *semantic* guess
from filename globs. Semantics-from-filenames is unreliable, so ~44 % of files fell
through to `_review` and the rest scattered across ~148 folders. v2 routes on
**extension / mimetype** first — attributes that are always knowable — so `_review`
holds only the genuinely-unknown tail (≈1 %). The taxonomy lives entirely in
`_inbox-routing.yaml`; the engine is generic.

## Architecture (hexagonal)

`janitor.py`:
- **CORE (pure)** — a `FILTERS` registry (each filter = `(FileMeta, param) -> dict|None`),
  `classify()` (quarantine → rules first-match → fallback), and `target_name()`
  templating. No I/O. Add a new way to match by registering one function — no deps.
- **EDGES** — `gather()` (stat/xattr/mimetype → a `FileMeta` parsed once at the
  boundary), `apply_move()` (mkdir + move + conflict handling), and `republish()`
  (Syncthing rescan of moved paths — see below).

## Syncthing rescan (republish)

After applying moves, the janitor POSTs `db/scan` for each touched subpath to the
local Syncthing REST API so other devices re-index **immediately**. Without this, a
moved file can stay invisible to the laptop/phone for up to `rescanIntervalS` (1 h)
because Syncthing's fs-watcher does not reliably catch moves into freshly-created
dirs. The API key is self-resolved from `SYNCTHING_CONFIG` (`config.xml`), so the
unit carries no secret; URL/folder default to `127.0.0.1:8384` / `000_inbox` and are
env-overridable. Best-effort: a rescan failure never fails the drain.

## Why server-only (single-writer)

`~/000_inbox` is a multi-writer Syncthing tree (laptop + server + LLM posts). Two
movers on two hosts would race the same path and Syncthing would emit
`.sync-conflict-*` copies — the exact failure that forced the brain vault onto a
single-writer hub. So exactly one host runs the drain. Enforced twice: the module is
only enabled on `hwc-server`, **and** `janitor.py` refuses `--apply` unless
`hostname == meta.owner_host` in the YAML (`--force` overrides, for manual runs).

## Structure

```
inbox-janitor/
├── index.nix    # Options + systemd oneshot service/timer (hwc.automation.inboxJanitor.*)
├── janitor.py   # The engine: pure classify() core + I/O edges; dry-run by default
└── README.md    # This file
```

The rule table (`_inbox-routing.yaml`) lives in `~/000_inbox`, not the repo — it is
live-editable config read each run, so tweaking routing needs no rebuild. Only changes
to `janitor.py` or `index.nix` require a server rebuild.

## Usage

```bash
# dry-run the loose-root drain (default; touches nothing)
inbox-janitor --config ~/000_inbox/_inbox-routing.yaml

# preview how the WHOLE tree would reclassify (migration planning)
inbox-janitor --config ~/000_inbox/_inbox-routing.yaml --all

# apply (server only; --all also reclassifies already-foldered files)
inbox-janitor --config ~/000_inbox/_inbox-routing.yaml --apply
```

## Enabling

```nix
# machines/server/config.nix
hwc.automation.inboxJanitor.enable = true;
hwc.automation.inboxJanitor.dryRun = false;   # after watching journalctl -u inbox-janitor
```

## Where a file goes (the write-side rule)

The router can only see intrinsic attributes, so it cannot tell a spec from a
scratch report — both are `.md`. That judgement belongs to whoever writes the
file. One question decides it: **does this thing already have a home?**

| Kind | Destination |
|---|---|
| Durable knowledge — worth looking up later, independent of the task | the **brain vault**, routed domain-first. Never the inbox. |
| Work product for a project that exists | **that project's home** — the repo, or `~/100_hwc` / `~/200_personal` / `~/300_tech` (each has its own `*_inbox`). Never the inbox. |
| Scratch — reports, diagnoses, audits, dumps | `downloads/agent/`, flat, derived name, expected to die there (60d → `_stale/`) |
| Arrivals from outside (browser downloads) | `downloads/` root; the janitor sorts by type. Not agents' concern. |

**Agents never create a directory under `downloads/`.** If output is big enough
to want a folder, it is a project by definition and belongs in a project home.
This one line would have prevented every structural mess this module has had:
the `sr-remediation-*` bundles at root, the bundles inside `agent/`, and the v1
domain folders. `report_unexpected_dirs()` is its check — a stray dir at root is
otherwise *invisible*, since the default drain walks loose files only and
`preview_skip_dirs` silently protects whatever it lists.

## Agent-output lifecycle

`downloads/agent/` is scratch with a terminal state, governed by three rules of
descending mechanical confidence:

1. **Naming** — agent output is named by derivation, `<domain>__<class>__<scoping_nouns>`,
   per the brain vault's `_charter/conversation_naming.md` (the same form handoffs
   use). The bucket stays flat: a derived name sorts itself into domain/class
   groups, so no folder tree is needed. Off-convention names route to
   `agent/_unsorted/` so they are visible rather than blending into the pile.
2. **Staleness** — `.md` untouched for 60d moves to `agent/_stale/`, a bounded
   holding pen. Revived by touching it (age stops matching) or by renaming it to
   the convention. **There is no delete tier and no automatic deletion**; see the
   rule-table comment for why the premortem cut it.
3. **Completion** — *a guideline, not a rule, and labeled as one*: session output
   is scratch until folded into the one living doc for its topic, then deleted
   rather than archived. Nothing enforces this; 303 accumulated files are the
   evidence that it is not self-enforcing. Only the authoring agent can know a
   file is done, so no sweeper attempts to infer it.

Supersession is deliberately **not** detected mechanically. A shared
`domain__class__scope` prefix looks like a supersession signal and is not — four
distinct live gdrive investigations share `datax__ops__gdrive__` — so inferring it
from filenames would delete parallel work while sounding precise.

## Changelog
- 2026-08-22: **`downloads/agent/` reorganized to `agent/<project>/<file>` and two
  reports added.** The flat bucket + `<domain>__<class>__<nouns>` filename convention
  measured **23% conformance (68 of 290 files) with zero near-misses** — no file used
  `__` with the wrong vocabulary, so nobody half-remembered the rule; they had never
  been shown it. `path-conventions.sh` matched `downloads/agent/*` and fell through
  with no rule, enforcing the directory and never the name (R4: enforced or guideline,
  nothing in between). It now enforces the project shape at write time.
  `report_agent_layout()` names loose files at agent/ root — under the new layout a
  directory is expected and a loose file is the violation, inverting
  `report_unexpected_dirs()`. `report_dangling_agent_citations()` names references to
  `downloads/agent/<path>` whose target is gone; it is the check the 2026-08-16
  premortem was missing when it observed that agent/ "already loses referenced
  artifacts on its own" — seven were dangling on first run, including a git bundle
  kept as a pre-migration backup and the only copy of ready-to-send customer reply
  drafts (three recovered from Syncthing versions). Tombstoned references (`[LOST`,
  `~~…~~`, "deleted") are skipped so the check goes quiet once a loss is acknowledged.
  Neither report deletes: the premortem's argument against a scheduled deleter here
  still stands. `preview_skip_dirs` now lists `agent` itself rather than seven
  individual bundles — **load-bearing**, not tidiness: without it a `--all` sweep
  matches every project file against `agent-unsorted` and flattens 357 files into
  `_unsorted/` in one run (measured). The `agent-stale`/`agent` rules were retired
  with the flat layout; `_stale/` was emptied (79 files, none referenced).
- 2026-08-16 (b): Added `report_unexpected_dirs()` — the default drain now names
  any top-level dir under `downloads/` that no rule produces and no skip entry
  claims. Report-only; never moves, never fails the drain. Finished the v1→PARA
  migration `index.nix` has described since v1: `business/`, `personal/` and the
  non-media `hwc/` subdirs drained to `~/100_hwc/100_inbox` and
  `~/200_personal/200_inbox` (`hwc_media/`'s 357 photos held back pending a
  considered destination); `events/`, `disconnect/`, `_quarantine/` and a stray
  `.claude/` retired. Top level went from 16 entries to 8.
- 2026-08-16: Fixed the self-collision that duplicated files to `_2` on any
  `--from`/`--all` re-run (in-place guard in `run()`); restores the documented
  idempotence invariant for re-runs. Rule table gains `agent-stale` (60d →
  `_stale/`, no delete tier) and splits `agent` into convention-compliant vs
  `_unsorted`, plus skip entries for the bundles inside `agent/`. Motivated by a
  brain-vault add/add conflict that red-lined `brain-vault-sync`, whose root
  cause was date-first naming carrying no aboutness.
- 2026-06-26: **v2** — declarative rewrite. Routes on intrinsic attributes
  (extension/mimetype) into ~6 flat buckets instead of semantic domain/class folders;
  `_review` dropped from ~44 % to ~1 %. Names preserved as-is (no date prefix). Added
  `agent/` bucket for Claude-Code output and a Syncthing `republish()` rescan that
  fixes the post-move index lag. Filter registry makes new matchers a one-function add.
- 2026-06-18: Initial module (v1). Timer drains `downloads/` root per `_inbox-routing.yaml`.
