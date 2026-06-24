# `/mnt/hot` Reconcile — human run checklist

> Companion to `reconcile.sh`. This is the procedure Eric (or whoever) runs
> when ready to consolidate `/mnt/hot` orphans into `/mnt/media` and prune
> the now-empty orphan dirs. **Nothing in this directory runs itself.**

## 0. Pre-flight

1. Read [`orphan-audit.md`](orphan-audit.md). Confirm the orphan list still
   matches what is actually on `/mnt/hot` today (`find /mnt/hot -maxdepth 1
   -mindepth 1`). If new orphans landed, add them to `ORPHAN_ROUTES` in
   `reconcile.sh` first and re-run this checklist from step 0.
2. Open `reconcile.sh` and review the `ACTIVE_HOT_RELS` array. It is the
   self-derived list of paths that the guard refuses to touch. Anything new
   under `/mnt/hot` that is owned by a NixOS module belongs in this list
   BEFORE you run the script.
3. Open `ORPHAN_ROUTES` and verify each `src|dst` route makes sense for what
   you actually want consolidated. Anything you do not want moved → comment
   it out.
4. Confirm `/mnt/media` has enough free space for the move
   (`df -h /mnt/media`; cross-check against `du -sh` of each orphan src).

## 1. Dry-run

```
DRY_RUN=1 ./docs/audits/mnt-hot/reconcile.sh
```

Expected output:

- `guard self-check passed (N active paths)`
- For each route: a `consolidate (MOVE): src -> dst` line followed by
  `DRY-RUN would run: mkdir -p ...` and
  `DRY-RUN would run: rsync -a --remove-source-files ...`.
- Phase 2 lines for each orphan that would be pruned (`prune (empty of
  media)` if it was already empty; otherwise `KEEP` because phase 1 in
  dry-run did not actually move anything).

Read every line. If anything looks wrong (a destination outside
`/mnt/media`, an active path showing up as an orphan, a missing src), STOP
and fix the data before continuing.

## 2. Read the log

The dry-run wrote a timestamped log to
`/var/log/mnt-hot-reconcile/reconcile-<UTC>.log`. Skim it — the on-disk log
is what you will need if the real run misbehaves and you need to roll back.

## 3. Real run

```
DRY_RUN=0 ./docs/audits/mnt-hot/reconcile.sh
```

- Phase 1 will `rsync --remove-source-files` each orphan into its
  destination. rsync removes each source file only after the destination
  byte-stream is verified — so a power-pull mid-run leaves the source
  intact for that file, never both copies (the contract: *we never leave
  both copies of anything*).
- Phase 2 will `rm -rf` each orphan dir that now has no media files. The
  guard refuses to delete anything under an active path.

If rsync errors on any file, the script aborts on the `set -e` — the
remaining routes are NOT processed. Investigate the rsync error before
re-running.

## 4. Verify

```
df -h /mnt/hot                       # space reclaimed
find /mnt/hot -maxdepth 1 -mindepth 1   # orphans should be gone
find /mnt/media -newer <log-file>       # media that just landed
```

Spot-check a few of the moved files with `cmp` against the on-disk log to
satisfy yourself that the rsync verify did its job. (rsync's
`--remove-source-files` already does this — the cmp is a paranoia check.)

## 5. Re-run for idempotency

```
DRY_RUN=0 ./docs/audits/mnt-hot/reconcile.sh
```

The second invocation should report `skip (orphan dir missing)` for every
route and exit cleanly with nothing to do. If it tries to act on anything,
phase 1 of the first run left something behind — investigate before
declaring done.

## 6. Tidy up

- Commit the timestamped logs somewhere durable if you want an audit trail.
- The orphan-audit doc is now stale; either update it or replace it with a
  follow-up snapshot.
