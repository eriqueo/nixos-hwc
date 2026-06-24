# docs/audits

Read-only audits whose deliverable is a written report (and, where applicable,
a dry-run remediation script) rather than a live configuration change. Each
audit lives in its own subdirectory.

## Structure

| Path | What it is |
|---|---|
| `media/duplicates-audit.md` | 2026-06-24 cross-pool duplicate audit of `/mnt/media` + `/mnt/hot` — method, totals, top-N reclaim table, hardlink-exclusion note. |
| `media/dedupe.sh` | Companion dry-run-by-default removal plan for the duplicate audit (`DRY_RUN=1` by default; never invoked by this repo). |

## Conventions

- Every audit ships at least a markdown report. Real numbers from real
  commands — no estimates.
- Any remediation script ships **dry-run by default** (`DRY_RUN="${DRY_RUN:-1}"`,
  `set -euo pipefail`) and is reviewed before being run by hand.
- Audits do not modify state outside `docs/audits/`.

## Changelog

- 2026-06-24 — initial `docs/audits/` tree; added `media/duplicates-audit.md`
  and `media/dedupe.sh` (cross-pool duplicate audit, 138.12 GiB reclaimable).
