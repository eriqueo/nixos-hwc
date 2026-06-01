# Audit: old-documents archive

You are auditing `/home/eric/200_personal/299_archive/old-documents/`
on `hwc-server`. This is a ~2.4GB archive of older personal documents.
Currently synced via Syncthing between `hwc-server` and `hwc-laptop`.
The goal is to characterize and propose a relocation/cleanup plan.

**Do not delete, move, or modify any files.** Your only write is the
report described at the end.

## What to investigate

1. **Top-level structure** — list immediate subdirs with `du -xhd 1`
   sorted by size. Each one is a category to evaluate independently.
2. **Composition by file type** — group by extension, top 10 by total
   bytes. Use `find -printf '%s %f\n' | awk` for speed.
3. **Age distribution** — bucket by mtime: `>10y / 5-10y / 2-5y /
   1-2y / <1y`. Anything <1y is suspicious in an "old-documents"
   archive and worth flagging.
4. **Document type clusters** — tax docs (`*tax*`, `*1099*`, `*w2*`,
   `*W-2*`), legal (`*contract*`, `*lease*`, `*will*`), receipts,
   scans (PDFs from scanner-style filenames), photos. Report counts +
   sizes.
5. **Likely duplicates** — name+size collisions across the tree (no
   hashing — too slow for 2.4G if there's lots of mixed types).
6. **Large outliers** — files >50MB. In a documents archive these are
   often misplaced media or installers.
7. **Junk** — `.DS_Store`, `Thumbs.db`, `__MACOSX/`, `.Trash/`,
   zero-byte files, `*.crdownload`. Counts + sizes.

## Tools

Direct shell access. Prefer `find / awk / sort / uniq / du` one-liners.
No need to read individual file contents.

## Deliverable

Write to:

```
/home/eric/.nixos/workspace/plans/disk-audit-old-documents-$(date +%Y-%m-%d).md
```

Report structure:

```markdown
# old-documents audit — <date>

## Summary
- Total: <X>G, <N> files
- Date range: <oldest> .. <newest>
- Bottom line: <one sentence>

## Top-level breakdown
<du -xhd 1 sorted output>

## Composition by file type
<top 10 extensions by bytes>

## Age distribution
| Bucket | Files | Bytes |
|---|---|---|

## Document type clusters
- Tax/financial: <N> files, <bytes>
- Legal: ...
- Scans: ...
- Receipts: ...
- Photos: ...
- Other: ...

## Duplicates suspects
<top 20 name+size collisions>

## Junk
<categories with counts and sizes>

## Proposed plan
### Keep in active sync (small, frequently referenced)
- The X% subset that's tax/legal/active

### Cold-archive to /mnt/backup/cold-archive/old-documents-<date>/
- Everything older than 5y AND not financial/legal

### Delete outright
- Junk categories above
- Anything reproducible

## Commands to run (review before executing)
\`\`\`bash
# Specific shell commands per above
\`\`\`

## Open questions
- Anything ambiguous that needs a human call
```

## Hard constraints

- Read-only on the target tree.
- Report file is the only write.
- Cap at ~10 min runtime; this tree is smaller so should be fast.
