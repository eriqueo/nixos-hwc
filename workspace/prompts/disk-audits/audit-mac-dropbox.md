# Audit: mac-dropbox archive

You are auditing `/home/eric/200_personal/299_archive/mac-dropbox/`
on `hwc-server`. This is a 26GB archive of an old Mac Dropbox account
that's currently being synced via Syncthing between `hwc-server` and
`hwc-laptop`. The goal is to characterize its contents and propose a
relocation plan so it stops clogging both home partitions.

**Do not delete, move, or modify any files.** Your only write is the
report described at the end.

## Known structure (from prior survey)

```
mac-dropbox/
├── md_documents_legacy/   19G   ← bulk; suspected: years-old docs
├── md_downloads/          5.5G  ← suspected: stale downloads, mostly junk
└── md_documents_root/     1.7G  ← suspected: active-ish docs
```

## What to investigate

For each of the three subdirs, find:

1. **Composition by file type** — group by extension, report the top 10
   by total bytes. Use `find ... -printf '%s %f\n'` + `awk` (avoid
   `du` per-extension, too slow).
2. **Age distribution** — `mtime` histogram in buckets:
   `>10y / 5-10y / 2-5y / 1-2y / <1y`. Anything older than 5y in an
   archive is a strong cold-storage candidate.
3. **Duplicate suspects** — files with identical name + size across
   different paths. Don't compute hashes (too slow for 26G); use
   `find -printf '%s\t%f\n' | sort | uniq -c | sort -rn | head -50`
   to find name+size collisions worth manual review.
4. **Obvious junk** — `.DS_Store`, `Thumbs.db`, `__MACOSX/`,
   `.Trash/`, `*.crdownload`, `*.partial`, zero-byte files. Count and
   total size.
5. **Big single files** — anything >100MB; report path + size. Often
   these are old disk images, ISOs, or video that belong elsewhere.
6. **Photo / video collections** — count of `*.{jpg,jpeg,heic,png,raw,cr2,nef,mov,mp4}`
   per subdir, total bytes. Mac Dropbox typically has photo dumps;
   these are duplicates of whatever's in Immich and should be
   reviewed for migration into Immich proper.

## Tools

You have direct shell access. Prefer one-shot bash pipelines using
`find`, `awk`, `sort`, `uniq`, `du`. Don't read individual files'
contents unless absolutely necessary.

## Deliverable

Write a single report to:

```
/home/eric/.nixos/workspace/plans/disk-audit-mac-dropbox-$(date +%Y-%m-%d).md
```

Report structure:

```markdown
# mac-dropbox audit — <date>

## Summary
- Total size: <X>G
- Files: <N>
- Date range: <oldest> .. <newest>
- Bottom-line recommendation: <one sentence>

## Per-subdir findings
### md_documents_legacy (19G)
- Top extensions: ...
- Age distribution: ...
- Notable big files: ...
- Junk: <N> files, <bytes>

### md_downloads (5.5G)
... same ...

### md_documents_root (1.7G)
... same ...

## Photo/video sub-collection
- Total: <N> files, <bytes>
- Suggested action: review for Immich import

## Duplicates
- Top 20 name+size collisions across the tree

## Junk to delete
- <category>: <count>, <bytes>, find ... command to enumerate

## Proposed relocation plan
### Cold-archive to /mnt/backup/cold-archive/mac-dropbox-<date>/
- md_documents_legacy/ in full (19G) — too old for hot access
- ...

### Migrate to Immich
- The N photos under <paths> totaling X GB

### Delete outright
- All .DS_Store / Thumbs.db / __MACOSX (X MB)
- ...

## Commands to run (review before executing)
\`\`\`bash
# Cold archive
sudo mkdir -p /mnt/backup/cold-archive/mac-dropbox-<date>
sudo mv /home/eric/200_personal/299_archive/mac-dropbox/md_documents_legacy \
    /mnt/backup/cold-archive/mac-dropbox-<date>/

# Junk deletion
find /home/eric/200_personal/299_archive/mac-dropbox -name '.DS_Store' -delete
...
\`\`\`

## Remove from Syncthing?
If the whole `mac-dropbox/` tree is being relocated/deleted, the
`200_personal` Syncthing folder definition in
`machines/{server,laptop}/config.nix` should still stay
(other subdirs of `200_personal/` are active). But mac-dropbox/ being
moved out will propagate as a delete from server to laptop, which
is what we want.
```

## Hard constraints

- No file deletions. No file moves. No file writes outside the
  report path.
- If you need to confirm something risky, write it as an open
  question in the report's "Questions" section at the bottom.
- Cap total runtime at ~20 minutes. If a `find` is taking >5 min,
  narrow the scope and note it in the report.
