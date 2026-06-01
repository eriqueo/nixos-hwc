# Audit: seagate-* archive dirs

You are auditing the three Seagate-named subdirs under
`/home/eric/200_personal/299_archive/` on `hwc-server`:

```
seagate-other/      346M
seagate-personal/   209M
seagate-work/       167M
```

These are dumps from old Seagate external drives (~700MB total).
Currently synced via Syncthing between `hwc-server` and `hwc-laptop`.
Small enough that a single audit can cover all three.

**Do not delete, move, or modify any files.** Your only write is the
report described at the end.

## What to investigate

For each `seagate-*` subdir:

1. **Top-level layout** — `tree -L 2 -d` or `find -maxdepth 2 -type d`
   so the reader gets a one-glance sense of what's in there.
2. **File type breakdown** — top 10 extensions by bytes.
3. **Age distribution** — `mtime` buckets `>10y / 5-10y / 2-5y / <2y`.
4. **Document type clusters** — same categories as the
   old-documents audit (tax/legal/scans/photos/other).
5. **Cross-subdir duplicates** — name+size collisions between
   `seagate-other` / `seagate-personal` / `seagate-work`. These three
   often have overlap because external drives got dumped multiple
   times.
6. **Junk** — `.DS_Store`, `Thumbs.db`, `__MACOSX/`, `.Trash/`,
   `System Volume Information/`, `$RECYCLE.BIN/`, zero-byte files.
7. **Large outliers** — anything >50MB.

## Tools

Direct shell access. `find / awk / sort / uniq / du` one-liners.
This tree is tiny (700MB) so even per-file MD5 hashing is feasible
for true duplicate detection if you want: `find ... -type f -exec
md5sum {} +` should complete in seconds.

## Deliverable

Write to:

```
/home/eric/.nixos/workspace/plans/disk-audit-seagate-$(date +%Y-%m-%d).md
```

Report structure:

```markdown
# seagate-* audit — <date>

## Summary
- Total: 700M across 3 subdirs, <N> files
- Bottom line: <one sentence>

## Per-subdir
### seagate-other (346M)
- Top-level dirs: ...
- Extensions: ...
- Age: ...
- Document clusters: ...

### seagate-personal (209M)
... same ...

### seagate-work (167M)
... same ...

## Cross-subdir duplicates (name+size or md5 collision)
<table of duplicate sets>

## Junk
<categories with counts and sizes>

## Proposed plan
### Merge unique survivors into a single archive
- After deduping, the survivors fit in ~<X> MB.

### Cold-archive merged result to /mnt/backup/cold-archive/seagate-merged-<date>/

### Delete all three seagate-* subdirs from Syncthing

## Commands to run (review before executing)
\`\`\`bash
# Specific commands per above
\`\`\`

## Open questions
- Anything ambiguous
```

## Hard constraints

- Read-only on the target tree.
- Report file is the only write.
- Cap at ~5 min runtime; tree is small.
