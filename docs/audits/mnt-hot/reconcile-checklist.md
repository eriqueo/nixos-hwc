# `/mnt/hot` reconcile — human run checklist

Companion to `reconcile.sh` (in this directory). The script is **dry-run by
default** and the agent that generated it has not executed it. Follow this
checklist before flipping `DRY_RUN=0`.

## 0. Context

The script does two things, in order:

1. **Consolidate.** For each orphan directory under `/mnt/hot` (not declared as
   active by any nixos module), rsync the contents into the matching
   `/mnt/media/<library>` destination using `--ignore-existing` (so an already
   present file is never overwritten and a re-run is a no-op).
2. **Prune.** For each orphan whose contents have been moved (i.e. the dir has
   no media files left), `rm -rf` the orphan. The script never touches any
   active path, and never touches `/mnt/hot` or `/mnt/media` themselves.

## 1. Review the active-paths set

Open `reconcile.sh`, find `ACTIVE_PATHS=(...)`. Confirm every path your nixos
config still uses is in that list. The header comment above the array names
the modules the agent self-derived from. Re-derive if a new service has
landed since 2026-06-24:

```bash
rg -n '/mnt/hot' ~/.nixos/{domains,machines,profiles}
```

If a path is missing, ADD it to `ACTIVE_PATHS` before running. The guard is
only as good as this list.

## 2. Review the orphan routes

`ORPHAN_ROUTES=(...)` lists each orphan dir and where its contents will be
copied. Confirm:

- Each orphan dir really is not used by any service.
- The destination under `/mnt/media` is the correct library for that
  content.

Add or remove entries as needed. The agent intentionally OMITTED
`/mnt/hot/ai` (it is service state, not media) — leave it that way unless
you have manually verified.

## 3. Dry-run

```bash
sudo DRY_RUN=1 /etc/nixos/docs/audits/mnt-hot/reconcile.sh
# (path adjusted to wherever the repo lives on the host; substitute as needed)
```

Verify in the output:

- Each `mkdir -p` looks right.
- Each `rsync` source/destination pair looks right.
- The guard self-check line `guard self-check passed` is present.
- No path under `/mnt/hot/{downloads,processing,surveillance,documents,…}`
  appears as an action target.

The log lives under `/var/log/mnt-hot-reconcile/reconcile-<UTC>.log`.

## 4. Read the log

```bash
less /var/log/mnt-hot-reconcile/reconcile-*.log
```

Search for `RUN:` / `DRY-RUN would run:` lines and confirm they only touch
expected paths. Search for any unexpected `SKIP` lines — they indicate the
guard caught something you should investigate before proceeding.

## 5. Real run

Once the dry-run output is fully understood:

```bash
sudo DRY_RUN=0 /etc/nixos/docs/audits/mnt-hot/reconcile.sh
```

## 6. Re-run for idempotency

Immediately run the script again with `DRY_RUN=0`. Because phase 1 uses
`rsync --ignore-existing`, the second run must be a no-op for the
consolidate phase. Because phase 2 already removed the orphan dirs, phase 2
should log `skip (already gone)` for every route. If either phase performs
any work on the second run, stop and investigate.

## 7. Done

Spot-check `/mnt/media/<dest>` to confirm the expected files arrived, then
remove this audit branch / merge the PR.
