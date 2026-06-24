# `docs/audits/` — point-in-time audits of system / media state

This directory holds read-only audits: a snapshot describing what is on disk
or in a system, plus an accompanying **dry-run** remediation script. Audits
**never** mutate the system they're auditing. Applying any remediation is
always a separate, human-gated step (set `DRY_RUN=0` and re-invoke).

This satisfies Charter Law 12 (touched domain README updated alongside
content changes): the audits domain owns its own README here.

## Structure

| Path                        | What                                                                                          |
|-----------------------------|-----------------------------------------------------------------------------------------------|
| `media/aux-audit.md`        | Aux libraries audit for `courses`, `podcasts`, `youtube`, `photos` (2026-06-24).              |
| `media/aux-reorg.sh`        | Dry-run fix plan for the aux audit. Refuses to apply without `DRY_RUN=0`; per-library gated. |

(The older `docs/audit/` directory — singular — holds the 2026-06-09 charter
merits / server-audit pair; new audits land here under the plural form
referenced by the nightly-builds gauntlet. Parallel audits for movies, TV,
music, and books exist on sibling `audit/media-*` branches and will land
here as they merge.)

## Conventions

- One Markdown audit + one shell remediation script per audit.
- The script defaults to `DRY_RUN=1` and prints what it *would* do. Apply
  with `DRY_RUN=0 ./<script>.sh`.
- Scripts set `set -euo pipefail` and refuse to run if `$ROOT` is missing.
- Audits cite the commands they ran and quote real output so a reviewer can
  reproduce them.

## Changelog

- 2026-06-24 — Aux libraries audit + dry-run reorg landed
  (`media/aux-audit.md`, `media/aux-reorg.sh`). Covers
  `/mnt/media/{courses,podcasts,youtube,photos}` against per-library
  standards. Script auto-actions one safe move (promote
  `Linux Security for Beginners/~Get Your Files Here !/` contents up one
  level); everything else (23× `.url` shortcuts, the `Gary Katz` channel
  duplicate, two Immich UUID backups under `photos/archive/`, the 3-way
  camera-dump collapse) is flagged for manual review only. `podcasts/`
  is empty and is a no-op.
