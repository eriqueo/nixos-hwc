# docs/audits

Read-only audits of on-disk media libraries against a single declared layout
standard. Each audit produces a report plus a **dry-run** rename/move plan that
Eric reviews and runs by hand — the audit itself never mutates `/mnt`.

## Structure

| Path | Purpose |
|------|---------|
| `media/movies-audit.md` | `/mnt/media/movies` audit against Plex/Jellyfin/Radarr `Title (Year)/Title (Year).ext` |
| `media/movies-reorg.sh` | Dry-run-by-default rename/move plan for `/mnt/media/movies` |

## Conventions

- Each audit declares its standard verbatim at the top.
- Counts and example paths are quoted from real `find`/`ls` output, not summarised.
- Reorg scripts default to `DRY_RUN=1`, are `set -euo pipefail`, and only print
  the moves they would make. They are never invoked from CI or nightly runs.

## Changelog

- 2026-06-24 — initial directory; added `media/movies-audit.md` and
  `media/movies-reorg.sh` for the `/mnt/media/movies` audit (nightly card
  `02-movies-audit`).
