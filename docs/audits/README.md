# `docs/audits/` — point-in-time audits of system / media state

This directory holds read-only audits: a snapshot describing what is on disk
or in a system, plus an accompanying **dry-run** remediation script. Audits
**never** mutate the system they're auditing. Applying any remediation is
always a separate, human-gated step (set `DRY_RUN=0` and re-invoke).

This satisfies Charter Law 12 (touched domain README updated alongside
content changes): the audits domain owns its own README here.

## Structure

| Path                                                     | What                                                       |
|----------------------------------------------------------|------------------------------------------------------------|
| `media/tv-audit.md`                                      | TV library audit vs. `Show/Season NN/SxxEyy` standard (2026-06-24). |
| `media/tv-reorg.sh`                                      | Dry-run fix plan for the TV audit. Refuses to apply without `DRY_RUN=0`. |

(The older `docs/audit/` directory — singular — holds the 2026-06-09 charter
merits / server-audit pair; new audits land here under the plural form
referenced by the nightly-builds gauntlet.)

## Conventions

- One Markdown audit + one shell remediation script per audit.
- The script defaults to `DRY_RUN=1` and prints what it *would* do. Apply
  with `DRY_RUN=0 ./<script>.sh`.
- Scripts set `set -euo pipefail` and refuse to run if `$ROOT` is missing.
- Audits cite the commands they ran and quote real output so a reviewer can
  reproduce them.

## Changelog

- 2026-06-24 — Added `media/tv-audit.md` + `media/tv-reorg.sh` (nightly-builds
  card `03-tv-audit`).
