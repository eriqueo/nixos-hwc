# docs/audits — repo audits and inventories

Point-in-time inventories and classification reports that other work depends on
as a source of truth. Each subdirectory covers a specific surface; the files
inside are dated, machine-reproducible reports, not living code.

## Structure

| Path                       | Purpose                                                              |
| -------------------------- | -------------------------------------------------------------------- |
| `media/inventory.md`       | `/mnt/media` top-level dirs classified managed/staging/unknown, with declaring module references and sizes. Source of truth for the /mnt/hot reconcile check and media cleanup cards. |

## Conventions

- Every audit doc cites the command(s) that produced it so it can be re-run.
- Tables use `|`-delimited markdown.
- Classifications: **managed** (declared by a module), **staging** (funnel
  buffer), **unknown** (no module reference — watch-list).

## Changelog

- 2026-06-24: Add `media/inventory.md` (nightly-builds card 06 —
  /mnt/media inventory + managed-vs-unknown classification).
