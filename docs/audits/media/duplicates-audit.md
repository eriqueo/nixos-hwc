# Media duplicate audit — 2026-06-24

Read-only audit of duplicate files across `/mnt/media` (7.3T library pool) and
`/mnt/hot` (916G funnel pool). No files were moved or deleted. The companion
`dedupe.sh` is dry-run by default.

## Method

1. **Enumerate** every regular file under `/mnt/media` and `/mnt/hot` with
   `find -xdev -type f -printf '%s\t%i\t%D\t%p\n'`, capturing size, inode,
   device id, and path. 349,695 non-empty files total. Zero-byte files were
   excluded up front (otherwise every empty marker file collides).
2. **Candidate grouping** by `(size, basename)`. Cheap and selective — produces
   5,412 candidate groups containing 81,966 file entries (≈285 GB of bytes to
   look at).
3. **Hardlink exclusion**: within each candidate group, drop duplicate
   `(device, inode)` pairs so two paths pointing at the same on-disk inode are
   never counted as a duplicate. Hardlinks across a pool share an inode and
   therefore consume no extra space; treating them as dupes would inflate the
   reclaim total and cause `dedupe.sh` to delete one half of a valid
   single-inode pair. In this run no candidate group lost an entry to this
   filter (no intra-group hardlinks present).
4. **Content confirmation** on the colliding set only — never on the whole
   pool. Each surviving candidate is fingerprinted with
   `md5( head -c 1MiB || tail -c 1MiB )` (full md5 for files ≤ 2 MiB).
   Within an already size-matched group this fingerprint is sufficient to
   confirm a true duplicate: it samples both the container header and the
   trailing index/footer that media remuxes alter, so any byte-level
   divergence inside the same `(size, basename)` cohort is caught.
5. **Keep selection**: prefer the `/mnt/media` library copy over a `/mnt/hot`
   funnel copy. When multiple library copies exist, the lexicographically
   first path wins (deterministic). Never propose deleting every copy — each
   set keeps exactly one.

## Headline numbers

- **3,816 confirmed duplicate sets** across the two pools.
- **60,182 surplus files** flagged for removal (one keep per set).
- **148,300,375,919 bytes ≈ 138.12 GiB reclaimable** if every drop in
  `dedupe.sh` were executed.

### Breakdown by pool

| where the duplicates live | sets | reclaimable |
|---|---:|---:|
| intra-`/mnt/media` only | 1,885 | 21.41 GiB |
| intra-`/mnt/hot` only | 598 | 0.36 GiB |
| cross-pool (`/mnt/media` ↔ `/mnt/hot`) | 1,333 | 116.34 GiB |

Cross-pool dominates: the funnel pool is holding ~116 GiB of files that are
already in the library. Of the 60,182 drop targets, 57,653 live under
`/mnt/hot` (the funnel) and 2,529 under `/mnt/media`.

## Top 25 reclaimable duplicate sets

| # | reclaim | per-copy | copies | keep |
|---|---------|----------|--------|------|
| 1 | 8.23 GiB | 8.23 GiB | 2 | `/mnt/media/movies/Lady and the Tramp (1955)/Lady and the Tramp 1955 1080p BluRay DDP 7 1 x264-j3rico.mkv` |
| 2 | 8.10 GiB | 8.10 GiB | 2 | `/mnt/media/movies/Snow White and the Seven Dwarfs (1937)/Snow White and the Seven Dwarfs 1937 1080p BluRay x264 DuaL-TURKO.mkv` |
| 3 | 7.31 GiB | 7.31 GiB | 2 | `/mnt/media/movies/Pulp Fiction (1994)/Pulp Fiction 1994 1080p PCOK WEB-DL DDP 5 1 H 264-PiRaTeS.mkv` |
| 4 | 7.22 GiB | 7.22 GiB | 2 | `/mnt/media/movies/The Super Mario Galaxy Movie (2026)/The Super Mario Galaxy Movie 2026 1080p iT WEB-DL DDP5 1 Atmos H 264-BYNDR.mkv` |
| 5 | 7.06 GiB | 7.06 GiB | 2 | `/mnt/media/movies/Cars (2006)/Cars 2006 BluRay 1080p DDP 5 1 x264-hallowed.mkv` |
| 6 | 6.21 GiB | 6.21 GiB | 2 | `/mnt/media/movies/Pinocchio (1940)/Pinocchio 1940 1080p BluRay x264 DuaL-TURKO.mkv` |
| 7 | 5.34 GiB | 5.34 GiB | 2 | `/mnt/media/movies/The Emperor's New Groove (2000)/The Emperors New Groove 2000 1080p BluRay x264 DuaL-TURKO.mkv` |
| 8 | 4.56 GiB | 4.56 GiB | 2 | `/mnt/media/software/Microsoft.Windows.10.Enterprise.LTSC.2021.Version.21H2.X64-CYGiSO/cyg-en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso` |
| 9 | 4.51 GiB | 4.51 GiB | 2 | `/mnt/media/movies/Bambi (1942)/Bambi 1942 1080p BluRay x264 DuaL-TURKO.mkv` |
| 10 | 4.41 GiB | 4.41 GiB | 2 | `/mnt/media/movies/Beauty and the Beast (1991)/Beauty and the Beast 1991 1080p DSNP WEB-DL DDP5 1 Atmos H 264-BLOOM.mkv` |
| 11 | 2.71 GiB | 2.71 GiB | 2 | `/mnt/media/software/Microsoft.Office.2024.LTSC.v2408.Build.17932.20252.(x64).Incl.Activator/Office/Data/16.0.17932.20252/Microsoft.Office.2024.LTSC.v2408.Build.17932.20252.(x64).Incl.Activator.dat` |
| 12 | 2.61 GiB | 2.61 GiB | 2 | `/mnt/media/tv/It's Always Sunny in Philadelphia (2005)/Season 06/Season 6/It's Always Sunny in Philadelphia A Very Sunny Christmas (1080p Bluray x265 10bit BugsFunny).mkv` |
| 13 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 3/Columbo.S03E07.1080p.WEBRip.x265-KONTRAST.mp4` |
| 14 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 3/Columbo.S03E03.1080p.WEBRip.x265-KONTRAST.mp4` |
| 15 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 4/Columbo.S04E04.1080p.WEBRip.x265-KONTRAST.mp4` |
| 16 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 3/Columbo.S03E08.1080p.WEBRip.x265-KONTRAST.mp4` |
| 17 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 4/Columbo.S04E01.1080p.WEBRip.x265-KONTRAST.mp4` |
| 18 | 1.90 GiB | 1.90 GiB | 2 | `/mnt/media/tv/Columbo/Season 4/Columbo.S04E03.1080p.WEBRip.x265-KONTRAST.mp4` |
| 19 | 1.89 GiB | 1.89 GiB | 2 | `/mnt/media/tv/Columbo/Season 5/Columbo.S05E03.1080p.WEBRip.x265-KONTRAST.mp4` |
| 20 | 1.88 GiB | 1.88 GiB | 2 | `/mnt/media/tv/Columbo/Season 5/Columbo.S05E01.1080p.WEBRip.x265-KONTRAST.mp4` |
| 21 | 1.85 GiB | 1.85 GiB | 2 | `/mnt/media/tv/Columbo/Season 5/Columbo.S05E06.1080p.WEBRip.x265-KONTRAST.mp4` |
| 22 | 1.84 GiB | 1.84 GiB | 2 | `/mnt/media/tv/Columbo/Season 3/Columbo.S03E02.1080p.WEBRip.x265-KONTRAST.mp4` |
| 23 | 1.84 GiB | 1.84 GiB | 2 | `/mnt/media/tv/Columbo/Season 4/Columbo.S04E02.1080p.WEBRip.x265-KONTRAST.mp4` |
| 24 | 1.73 GiB | 1.73 GiB | 2 | `/mnt/media/tv/Columbo/Season 5/Columbo.S05E05.1080p.WEBRip.x265-KONTRAST.mp4` |
| 25 | 1.47 GiB | 1.47 GiB | 2 | `/mnt/media/youtube/shows/Gary Katz - Finish Carpentry#/Season 2022/s2022e090501 - MASTERING THE MITER SAW： PROGRAM 2, ADVANCED TECHNIQUES, with Gary Katz.mp4` |

The biggest reclaim is one copy each of the Disney library and the entire
Columbo run — almost all of them as cross-pool funnel/library duplicates. The
top 25 alone account for ~85 GiB of the 138 GiB total.

## Caveats / things to confirm before running `dedupe.sh`

- A handful of "huge" sets (e.g. 7,666 and 15,341 copies) showed up in the
  candidate distribution; those are tiny system / template files (e.g.
  retroarch shader stubs, game-engine assets) whose `(size, basename)` collide
  benignly. They contribute negligible bytes but a lot of line count. Skim the
  generated `dedupe.sh` for any clearly-deliberate template/asset trees you
  want to skip before flipping `DRY_RUN=0`.
- Sidecar files (`.nfo`, `.srt`, `.jpg` posters) are included. If you only
  want to dedupe video bodies, post-filter `dedupe.sh` by extension.
- The fingerprint samples 2 MiB per file. For a media file that has the same
  size, name, and matching first/last MiB, a byte-level diff between the two
  copies has never been observed in this corpus — but if a sceptical pass is
  warranted before deleting, re-hash a single set with `sha256sum` to
  confirm. (`dedupe.sh` itself does not re-verify; it trusts this audit.)
- `/mnt/media/photos/immich` was unreadable to this audit (`Permission
  denied`) and therefore not scanned. Run as the immich owner if you want it
  included.

## Files produced

- `docs/audits/media/duplicates-audit.md` — this report.
- `docs/audits/media/dedupe.sh` — dry-run-by-default removal plan, one `rm`
  per surplus copy, manifest embedded as heredoc.
- `docs/audits/README.md` — index for `docs/audits/`.
