# Media reorg/cleanup manifests

Generated one-off shell manifests moved out of `docs/` (2026-07-05 audit —
executable scripts are not documentation). Companions to the audit notes in
`docs/audits/`.

- `dedupe.sh` — 60k-line generated `rm` manifest (3,816 dupe sets, ~138 GiB
  reclaimable). **DRY_RUN=1 by default. Never executed as of 2026-07-05** —
  decide: review + run, or delete. Regenerate before running if the library
  has changed since 2026-06-24.
- `aux-reorg.sh`, `books-reorg.sh`, `tv-reorg.sh` — library reorg manifests.
- `mnt-hot-reconcile.sh` — /mnt/hot reconcile pass.
- `2026-06-09-cleanup.sh` — repo/server cleanup from the 2026-06-09 audit.
