# `docs/audits/` — point-in-time audits of system / media state

This directory holds read-only audits: a snapshot describing what is on disk
or in a system, plus an accompanying **dry-run** remediation script. Audits
**never** mutate the system they're auditing. Applying any remediation is
always a separate, human-gated step (set `DRY_RUN=0` and re-invoke).

This satisfies Charter Law 12 (touched domain README updated alongside
content changes): the audits domain owns its own README here.

## Structure

| Path                          | What                                                                                          |
|-------------------------------|-----------------------------------------------------------------------------------------------|
| `media/aux-audit.md`          | Aux libraries audit — `courses`, `podcasts`, `youtube`, `photos` (2026-06-24).                |
| `media/aux-reorg.sh`          | Dry-run fix plan for the aux audit (per-library gated; `DRY_RUN=1`).                          |
| `media/books-audit.md`        | Books + audiobooks audit vs readarr `Author/Title` layout (2026-06-24).                       |
| `media/books-reorg.sh`        | Dry-run fix plan for the books audit.                                                         |
| `media/duplicates-audit.md`   | Cross-pool duplicate audit (`/mnt/media` + `/mnt/hot`), ~138 GiB reclaimable (2026-06-24).    |
| `media/dedupe.sh`             | Dry-run dedupe plan for the duplicates audit.                                                  |
| `media/inventory.md`          | `/mnt/media` top-level inventory + managed/staging/unknown classification (2026-06-24).       |
| `media/tv-audit.md`           | TV library audit vs `Show/Season NN/SxxEyy` (2026-06-24).                                      |
| `media/tv-reorg.sh`           | Dry-run fix plan for the TV audit.                                                            |
| `mnt-hot/orphan-audit.md`     | `/mnt/hot` orphan/crust audit — ~86 G reclaimable; consolidate + safe-delete lists (2026-06-24). |

(The older `docs/audit/` directory — singular — holds the 2026-06-09 charter
merits / server-audit pair; new audits land here under the plural form
referenced by the nightly-builds gauntlet. Three more 2026-06-24 audits —
`media/music-audit.md` + `media/music-reorg.sh`, `media/movies-audit.md` +
`media/movies-reorg.sh`, and `mnt-hot/active-paths.md` — are on sibling
`audit/media-music`, `audit/media-movies`, and `audit/hot-funnel-map` branches
(PRs #66–#68) and will land here as they merge.)

## Conventions

- One Markdown audit + one shell remediation script per audit.
- The script defaults to `DRY_RUN=1` and prints what it *would* do. Apply
  with `DRY_RUN=0 ./<script>.sh`.
- Scripts set `set -euo pipefail` and refuse to run if `$ROOT` is missing.
- Audits cite the commands they ran and quote real output so a reviewer can
  reproduce them.

## Changelog

- 2026-06-24 — Nightly-builds media/hot audit batch landed (6 audits):
  aux libraries (`media/aux-*`), books + audiobooks (`media/books-*`),
  cross-pool duplicates (`media/duplicates-audit.md`, `media/dedupe.sh`),
  `/mnt/media` inventory (`media/inventory.md`), TV library (`media/tv-*`),
  and `/mnt/hot` orphan/crust (`mnt-hot/orphan-audit.md`). All are read-only
  reports + dry-run scripts; nothing under `/mnt` was mutated. Three sibling
  audits (music, movies, hot funnel-map) are pending on PRs #66–#68.
