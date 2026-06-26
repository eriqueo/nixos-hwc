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

Organized bucket folders are never swept, so the pass is idempotent.

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

## Changelog
- 2026-06-26: **v2** — declarative rewrite. Routes on intrinsic attributes
  (extension/mimetype) into ~6 flat buckets instead of semantic domain/class folders;
  `_review` dropped from ~44 % to ~1 %. Names preserved as-is (no date prefix). Added
  `agent/` bucket for Claude-Code output and a Syncthing `republish()` rescan that
  fixes the post-move index lag. Filter registry makes new matchers a one-function add.
- 2026-06-18: Initial module (v1). Timer drains `downloads/` root per `_inbox-routing.yaml`.
