# Aux media libraries audit — `courses`, `podcasts`, `youtube`, `photos`

Date: 2026-06-24. Read-only enumeration of the four `/mnt/media` libraries
that no *arr strictly manages, plus per-library structural deviations and
dedupe candidates. Nothing under `/mnt` was modified. Companion script:
`aux-reorg.sh` (dry-run-by-default; not executed by this audit).

Scope: `/mnt/media/{courses,podcasts,youtube,photos}` only. Movies, TV,
music, and books each have their own audit doc + reorg plan.

## courses

Standard adopted: `Course Title/<lesson-folder>/NN - Lesson Title.ext`,
where `<lesson-folder>` is either flat (small course) or a single layer of
section folders (`Season NN - Name` or `NN-Section Title`). Companion files
(`.pdf`, `.rtf`, `.txt`, `.zip`, `.epub`) live next to the lessons they
belong to; loose `.url` shortcuts and `~Get Your Files Here !`-style
wrappers from torrent dumps are flagged for removal.

Top-level counts (from `find … -type f | wc -l` and `du -sh`):

| Course                                       | Files | Size  |
|----------------------------------------------|------:|------:|
| `ADHD 30 Days to the Life You Deserve/`      |     2 | 2.5G  |
| `ChatGPT Mastery Course/`                    |   156 | 17G   |
| `Dr K's Guide to Mental Health - ADHD/`      |   102 | 14G   |
| `Linux Security for Beginners/`              |    11 | 302M  |
| `Matt.Smith.The.Mobility.Flexibility.Toolkit/` | 124 | 2.0G  |
| `Ultimate Time Management Toolkit/`          |     2 | 3.0M  |

File-type breakdown across all of `courses/` (top extensions):

```
    211 .mp4
     70 .pdf
     46 .txt
     32 .png
     23 .url
      7 .rtf
      4 .jpg
      1 .zip
      1 .torrent
      1 .html
      1 .epub
```

Structural deviations:

- **`Linux Security for Beginners/~Get Your Files Here !/`** — the entire
  course content is one level deeper than the rest of the library, inside a
  Tutorialsplanet-style wrapper directory (`~Get Your Files Here !`). The
  course itself is sane (`9. Why Passwords.mp4`, `1. Introduction.html`),
  but the wrapper folder should be removed and its contents promoted to the
  course root.
- **`ChatGPT Mastery Course/UPDATE 1/`** — the "UPDATE 1" tier duplicates
  the section layout of the parent (`02-Beginners Prompting`,
  `03-Advanced Prompting`, plus new `09-FollowUp Prompting`,
  `10-Custom Instructions`, `12-Charts with ChatGPT`). Cross-checking the
  filenames will show whether the parent sections are stale and should be
  retired in favour of the UPDATE 1 versions; flagged for manual review.
- **`ADHD 30 Days to the Life You Deserve/`** is an undelivered
  course — only a `Read Me.txt` and an unextracted
  `ADHD 30 Days To The Life You Deserve.zip` (per `find … -type f`); should
  be either extracted into a `Course Title/NN - Lesson.ext` layout or
  removed.
- **`Ultimate Time Management Toolkit/`** is similarly minimal — one
  `.epub` and one "support my listings" advert `.txt`. The `.txt` is junk;
  the `.epub` belongs under `books/ebooks/` rather than `courses/` (this is
  a book, not a video course).

Junk-file candidates (23× `.url` advertising shortcuts):

```
/mnt/media/courses/ChatGPT Mastery Course/.../PimpMyMoney.url
/mnt/media/courses/ChatGPT Mastery Course/.../Telegram Channel for Business Courses.url
/mnt/media/courses/ChatGPT Mastery Course/Discord Community.url
/mnt/media/courses/ChatGPT Mastery Course/GroupBuys.url
/mnt/media/courses/Linux Security for Beginners/Get Bonus Downloads Here.url
```

(20× under `ChatGPT Mastery Course/`, 1× under
`Linux Security for Beginners/`, 1× per Update-1 section, etc.)

Dedupe candidates: none cross-course at the title level. The `UPDATE 1`
sub-tree under `ChatGPT Mastery Course/` is the only intra-course dedupe
candidate and is left for manual review (script flags, does not move).

## podcasts

Standard adopted: `Show/YYYY-MM-DD - Episode.ext`. The library is **empty**:

```
$ command ls -la /mnt/media/podcasts
total 8
drwxr-xr-x  2 eric users 4096 Apr  8 11:12 .
drwxr-xr-x 21 root root  4096 Jun 22 22:30 ..
```

Zero entries at depth 1; no files; no `Show/` subdirectory. Action: none.
The dir exists to host a future podcatcher (gPodder / Podgrab / AntennaPod
share). No reorg needed; no junk to flag. The reorg script's
`podcasts` section is a no-op stub.

## youtube

Standard adopted (already in use): Plex-tvshow layout — `shows/Channel/Season
YYYY/sYYYYeMMDDNN - title.ext` + sidecar `.nfo`, `.srt`, `.jpg`,
`.<title>-thumb.jpg`. The `.nfo` carries the YouTube uniqueid:

```xml
<uniqueid type="youtube" default="true">aH2FI5FJsv0</uniqueid>
```

This is yt-dlp output rewritten for Plex/Sonarr's "anime by date" pattern
(`SYYYYEMMDDNN`), not the classic yt-dlp archive style; it works because
Plex treats year-as-season natively. Keep the convention.

Counts:

```
youtube total file count: 1842
youtube size: 66G

      1 .keep        # /mnt/media/youtube/.keep — yt-dlp placeholder
    531 .jpg         # thumbnails + "-thumb" companions
    512 .nfo         # Plex metadata
    510 .mp4         # episodes
    288 .srt         # subtitles
```

Per-channel:

| Channel                              | Files | Note                            |
|--------------------------------------|------:|---------------------------------|
| `Curiosity show/`                    |   292 |                                 |
| `Danny Go!/`                         |   500 |                                 |
| `Gary Katz/`                         |    41 | canonical Gary Katz folder      |
| `Gary Katz - Finish Carpentry#/`     |    15 | **duplicate** — see below       |
| `Mystery Science/`                   |   993 |                                 |

Structural deviations:

- **`Gary Katz - Finish Carpentry#/`** is a duplicate channel folder. It
  shares two episodes verbatim with the canonical `Gary Katz/`:

  ```
  $ comm -12 <(find 'Gary Katz' -printf '%f\n' | sort -u) \
              <(find 'Gary Katz - Finish Carpentry#' -printf '%f\n' | sort -u)
  s2022e090500 - MASTERING THE MITER SAW: PROGRAM 1, FUNDAMENTALS, with Gary Katz.mp4
  s2022e090500 - MASTERING THE MITER SAW: PROGRAM 1, FUNDAMENTALS, with Gary Katz-thumb.jpg
  s2022e090501 - MASTERING THE MITER SAW: PROGRAM 2, ADVANCED TECHNIQUES, with Gary Katz.mp4
  s2022e090501 - MASTERING THE MITER SAW: PROGRAM 2, ADVANCED TECHNIQUES, with Gary Katz-thumb.jpg
  ```

  (Filenames also contain a fullwidth colon `：` — preserved here as `:` for
  legibility.) Beyond the four overlapping files, the `#` variant holds 11
  unique items (mostly `.jpg` thumbs) and the canonical folder holds 37
  unique items (the full `.mp4` set + `.nfo`/`.srt`). The `#` variant is the
  older partial scrape; the canonical `Gary Katz/` is the larger, complete
  one. The `#` suffix itself is also illegal-ish in many filesystem-aware
  agents (trailing-`#`).
- **Trailing `.keep` file at `/mnt/media/youtube/.keep`** — leftover empty
  marker. Harmless but pointless once `shows/` exists. Not a deviation
  worth a script entry.

Dedupe candidates: only the Gary Katz collision above. No cross-channel
filename clashes detected.

## photos

Standard adopted: dated buckets `YYYY/YYYY-MM-DD …` (matches the eight
existing `2008/`…`2016/` year folders), supplemented by event folders for
named trips (`Alaska/`, `Grand Canyon trip/`). Immich-backed UUID-named
content-addressed dirs do NOT belong in the human-curated tree.

Top-level counts:

| Path                                                   | Files  | Size  |
|--------------------------------------------------------|-------:|------:|
| `archive/`                                             | 31,213 | 68G   |
| `encoded-video/`                                       |      1 | 8.0K  |
| `external/`                                            | 34,285 | 131G  |
| `immich/`                                              |      0 | 4.0K  |
| `library/`                                             |      1 | 8.0K  |
| `profile/`                                             |      1 | 4.0K  |
| `thumbs/`                                              |      1 | 4.0K  |
| `.sha256sums.txt`                                      |      1 | 5.2M  |

File-type breakdown across all of `photos/`:

```
  39952 .jpg
   5842 .heic
   5134 .jpeg
   4533 .png
   4228 .webp
   4200 .mov
    778 .mp4
    175 .crw
    152 .gif
     90 .psd
     79 .cr2
     57 .bmp
     51 .db
     18 .pdf
     17 .avi
     14 .gz
      8 .immich
      7 .data
      4 .txt
      4 .json
```

Structural deviations:

- **`archive/42ce7cc4-56f5-4549-ad30-8a061747b269/`** (27G, 8,087 files) and
  **`archive/ff28bcb9-0346-4dba-a7b9-b92981d06920/`** (21G, 6,268 files) are
  Immich library backups — each contains the same two-character prefix
  fan-out (`01/`, `2b/`, `24/`, `8b/`, `06/` …) that Immich uses for
  content-addressed storage. These do not belong in a human-browsed
  archive; they are duplicates of Immich's own data and should either be
  re-anchored under `immich/` (which is currently empty owned by uid 999)
  or removed once Immich's own backups are confirmed.
- **Year folders coexist with topic/event folders without a divider.**
  `archive/{2008..2016}/` is the year set; alongside live `Alaska/`,
  `Banjo Era ` (trailing space, deliberate or not), `Camera Uploads/`,
  `Grand Canyon trip/`, `Masters/`, `old Pictures/`, `photosfrommeri/`,
  `Pics/`, `upload/`, `uploads/`. Recommend splitting:
  `archive/years/YYYY/` and `archive/events/<event>/` so the next sweep
  doesn't keep mixing them. (Out of scope for the reorg script — this is a
  conceptual split that should not be mechanically performed; flagged
  only.)
- **`archive/Camera Uploads/` (2 files), `archive/upload/` (83 files),
  `archive/uploads/` (0 files)** — three near-synonyms for the same
  semantic bucket. `uploads/` is empty (delete after confirmation);
  `Camera Uploads/` and `upload/` should be merged into a single
  `events/camera-dump/` (or processed and emptied).
- **`archive/Banjo Era ` (trailing space) and `archive/old Pictures/`** —
  illegible bucket names. The trailing space on `Banjo Era ` is a known
  source of shell-quoting bugs; rename to `Banjo Era/`.
- **`encoded-video/` and `archive/encoded-video/`** — two folders with the
  same name at different levels; both look like transcoder output staging.
  Flagged for manual review (not auto-merged).
- **`library/`, `profile/`, `thumbs/`, `archive/library/`,
  `archive/profile/`, `archive/thumbs/`** — each holds exactly one file (a
  hidden `.keep` placeholder or similar). These are Immich-orchestrated
  trees (uid 999 in `immich/`); the human archive should not have
  empty `library/profile/thumbs` directories at the photos root.
- **`external/laptop/{mt_family,md_family,by_era,by_trip,unsorted}/`** —
  this subtree is a snapshot of the laptop's photo organisation
  (semantic / by-trip / by-era / family-named), distinct from the dated
  `archive/` layout. It is internally consistent and should be kept as-is
  for now; once Immich is the source of truth, this whole subtree becomes a
  candidate for import-and-retire.
- **`.sha256sums.txt` (5.2M) at `/mnt/media/photos/.sha256sums.txt`** —
  pre-existing checksum manifest from an earlier dedupe pass. Keep; it's
  load-bearing for any future cross-tree dedupe.

Dedupe candidates:

1. The two UUID `archive/<uuid>/` Immich backups (28G + 21G = 48G
   reclaimable once Immich confirms its own backup elsewhere).
2. `archive/Camera Uploads/` + `archive/upload/` + `archive/uploads/`
   (collapse three buckets into one or zero).
3. `encoded-video/` vs `archive/encoded-video/` (one file each at root,
   flagged for manual reconcile).

Existing dedupe-report dirs:

```
$ command ls /mnt/media/photos/archive/.dedup-reports
2026-02-26_202436
2026-02-27_085927
```

These are outputs from prior dedupe sweeps; preserved untouched.

## Summary

| Library    | Top-level entries | Files (total) | On-disk | Reorg actions |
|------------|------------------:|--------------:|--------:|---------------|
| `courses`  |                 6 |           397 |   ~36G  | 1 wrapper-dir promotion, junk-file flag (23× `.url`), 2 misplaced/empty courses flagged |
| `podcasts` |                 0 |             0 |     0   | none (empty) |
| `youtube`  |   2 (`shows/`, `.keep`) | 1,842 |   66G   | 1 channel-folder collision (Gary Katz) flagged; no auto-merge |
| `photos`   |                 8 |       ~65,500 |  ~200G  | 2 Immich UUID backups flagged (~48G recoverable); 3-way Camera-Uploads merge flagged; assorted empty-`.keep` dirs |

Total: 4 standards documented, ~67,700 files enumerated, ~302G surveyed.
Companion script `aux-reorg.sh` is dry-run-by-default; nothing under `/mnt`
was touched during this audit.
