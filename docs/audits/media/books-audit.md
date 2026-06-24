# `/mnt/media/books` — audit vs Readarr-style `Author/Title/Title.ext` (2026-06-24)

> Read-only audit. Nothing under `/mnt` was moved, renamed, or deleted.
> Companion remediation script: [`books-reorg.sh`](./books-reorg.sh) (dry-run by default).

## Standard

The repo runs **Bookshelf** (a Readarr revival, image
`ghcr.io/pennydreadful/bookshelf:hardcover`) — see
`domains/media/readarr/sys.nix`. It mounts `/mnt/media/books → /books` as one
root and is expected to drive the canonical Readarr layout:

```
<library>/<Author Name>/<Title>/<Title>.<ext>
```

- `<library>` = `audiobooks/` (audio formats: `.m4b`, `.m4a`, `.mp3`) or
  `ebooks/` (text formats: `.epub`, `.mobi`, `.pdf`).
- `<Author Name>` is a single directory keyed off the primary author.
- `<Title>` directory holds exactly one logical work; multi-disc/multi-file
  audiobooks may have subfolders (`Disc N`) but the *book* directory itself is
  one title.
- Format mixing inside one `<Title>/` is allowed (`.m4b` + `.epub` for the
  same book), but the *same title* should not appear twice across libraries
  with different filenames (cross-format duplicate).
- Loose files at `audiobooks/` or `ebooks/` root are non-conformant; so are
  topic / shelf / dump directories (`coding/`, `Survival, Homesteading & .../`,
  `ebooks/calibre/`).

## Commands run

```
find /mnt/media/books -maxdepth 3 -type d
find /mnt/media/books -type f -not -path '*/.audiobookshelf-metadata/*' \
  | sed -n 's/.*\.\([a-zA-Z0-9]\+\)$/\1/p' | tr '[:upper:]' '[:lower:]' \
  | sort | uniq -c | sort -rn
find /mnt/media/books/{audiobooks,ebooks} -maxdepth 1 -mindepth 1 -type d
for d in /mnt/media/books/audiobooks/*/; do
  subc=$(find "$d" -maxdepth 1 -mindepth 1 -type d | wc -l)
  echo "$subc  $d"
done
du -sh /mnt/media/books/{audiobooks,ebooks}
```

All counts below come from those commands at audit time.

## Top-level layout

```
/mnt/media/books/
├── audiobooks/                       # 15 author/title dirs (one library root)
├── ebooks/                           # 3 topic dirs + 2 loose epubs at root
└── .audiobookshelf-metadata/         # Audiobookshelf sidecar — IGNORE
```

Note: `.audiobookshelf-metadata/` is the Audiobookshelf scanner cache (covers,
items, logs, backups). It is **not** library content and is intentionally
ignored by this audit and the companion script.

## Counts

| Library      | Size | Dir count (depth 1) | Author/Title-shaped | Author-Title flat | Other |
|--------------|------|---------------------|---------------------|-------------------|-------|
| `audiobooks` | 6.9G | 15                  | 5                   | 7                 | 3     |
| `ebooks`     | 5.6G | 3 dirs + 2 loose    | 0                   | 0                 | 3     |

File-extension census (excluding `.audiobookshelf-metadata/`):

| Library      | mp3 | m4b | m4a | epub | mobi | pdf | other        |
|--------------|----:|----:|----:|-----:|-----:|----:|--------------|
| `audiobooks` | 374 |  54 |   2 |    2 |    0 |   1 | jpg/nfo/cue/txt |
| `ebooks`     |   0 |   0 |   0 |   40 |   18 | 168 | jpg/opf/db/json/txt |

Library totals: **6 audio formats / 432 files** in `audiobooks`, **6 text
formats / 236 files** in `ebooks`. (Counts are file-level, not title-level.)

## Findings

### F1. Titles not under an `Author/` folder (audiobooks)

Eleven of fifteen `audiobooks/` entries flatten Author and Title into one
directory name instead of nesting Title under Author. Readarr will read each
of these as a *single* "author" whose name happens to contain a hyphen.

Author-Title flat (`<Author> - <Title>`), would split into `Author/Title/`:

```
audiobooks/Brian Tracy - The Miracle of Self Discipline The 'No Excuses' Way to Getting Things Done/
audiobooks/Cal Newport - So Good They Can't Ignore You/
audiobooks/Elaine Aron - The Highly Sensitive Child (Unabridged)/
audiobooks/Gerber, Michael E. - The E-Myth Revisited - Why Most Small Businesses Don't Work and What to Do About It/
audiobooks/Johann Hari - Stolen Focus Why You Can't Pay Attention—and How to Think Deeply Again/
audiobooks/Robert Greene - The 48 Laws of Power/
audiobooks/William F. Buckley - God and Man at Yale - The Superstitions of Academic Freedom (Unabridged)/
```

Other / no parseable author (manual review — script will not guess):

```
audiobooks/01 -  Master & Commander/                              # leading "01 - " prefix; Patrick O'Brian, vol 1
audiobooks/Count of Monte Cristo - Dumas - Audiobook - Richard Matthews/  # narrator suffix
audiobooks/Philosophy of Thomas Aquinas/                          # no author dir
audiobooks/The Courage to Be Disliked/                            # no author dir (Kishimi/Koga)
```

Already Author/Title-shaped (compliant, leave alone):

```
audiobooks/Cal Newport/{Deep Work,Digital Minimalism,Slow Productivity}/
audiobooks/C.S. Lewis/{A Grief Observed,Mere Christianity}/
audiobooks/G.K. Chesterton/Orthodoxy/
audiobooks/Patrick O'Brian/{The Golden Ocean,The Final, Unfinished Voyage of Jack Aubrey}/
audiobooks/Gerber, Michael E. - .../{The E-Myth Revisited (Disc 1..7)}/  # Author-Title flat but disc-split inside
```

Note: the Gerber tree *does* have title-level subdirectories, but they are
disc splits of one title, not multiple titles — promoting them to "titles"
would invent six new books. The script renames the flat Author-Title to
`Gerber, Michael E./The E-Myth Revisited - .../` and keeps the disc folders
underneath.

### F2. Loose files at library root

Two loose ebooks at `ebooks/` with no Author dir:

```
ebooks/Cal Newport - Slow Productivity.epub
ebooks/The Man Who Was Thursday - G.K. Chesterton.epub
```

There are **no loose audiobook files** at `audiobooks/` root.

### F3. Non-Author shelves and a nested library dump (ebooks)

The `ebooks/` library has three top-level directories, none of which is an
Author:

```
ebooks/coding/                                # topic shelf — 3 subdirs (publisher bundles), 26 pdf
ebooks/Survival, Homesteading & Self-Sufficiency/   # topic shelf — ~140 pdf flat at one level
ebooks/ebooks/calibre/                        # nested Calibre library dump inside ebooks/
```

`ebooks/coding/` example:

```
ebooks/coding/Become a Python Expert 2024 by Pearson Core/PDFs/Learn Python 3 the Hard Way.pdf
ebooks/coding/Hacking 2024 by No Starch/...
ebooks/coding/Math for Programmers 2024 by Manning/...
ebooks/coding/readme.txt
ebooks/coding/trackers.txt
```

`ebooks/ebooks/calibre/` is a full Calibre library dump (its own
`metadata.db`, `.calnotes/`, plus Author-shaped subdirs):

```
ebooks/ebooks/calibre/G.K. Chesterton/Father Brown Stories (1)/Father Brown Stories - G.K. Chesterton.epub
ebooks/ebooks/calibre/G.K. Chesterton/William Blake (2)/William Blake - G.K. Chesterton.epub
ebooks/ebooks/calibre/metadata.db
ebooks/ebooks/calibre/metadata_db_prefs_backup.json
```

None of these three groups is safe to auto-rename — they are decisions, not
mechanical renames. The script prints them under a "manual review" block.

### F4. Cross-format duplicate titles

Going by basename across both libraries, one clear cross-format duplicate:

- **Cal Newport — Slow Productivity**
  - audiobook (multi-mp3): `audiobooks/Cal Newport/Slow Productivity/…`
  - ebook (single epub):   `ebooks/Cal Newport - Slow Productivity.epub`

One near-duplicate (different titles by the same author across formats):

- **G.K. Chesterton**
  - audiobook: `audiobooks/G.K. Chesterton/Orthodoxy/…`
  - ebooks:    `ebooks/The Man Who Was Thursday - G.K. Chesterton.epub`,
               `ebooks/ebooks/calibre/G.K. Chesterton/Father Brown Stories (1)/`,
               `ebooks/ebooks/calibre/G.K. Chesterton/William Blake (2)/`

These should land at the same `<Author>/` path once the calibre dump is
folded in (out of scope for this audit — the script flags it).

### F5. Audiobooks library — Author/Title compliance summary

Of 15 top-level entries in `audiobooks/`:

- **5** are already `Author/` directories with `Title/` children
  (Cal Newport, C.S. Lewis, G.K. Chesterton, Patrick O'Brian, Gerber/E-Myth*).
- **7** are flat `Author - Title` directories that should split into
  `Author/Title/` (F1 list above).
- **3** have no parseable author or carry narrator/disc-prefix metadata in
  the dir name (`01 -  Master & Commander`, `Count of Monte Cristo - Dumas
  - Audiobook - Richard Matthews`, `Philosophy of Thomas Aquinas`, `The
  Courage to Be Disliked`).

(*) Gerber is technically Author-Title flat at the top dir, but the children
underneath are disc splits of *one* title, so it counts as "already has
title-level structure" for purposes of renaming.

### F6. Audiobookshelf sidecar

`/mnt/media/books/.audiobookshelf-metadata/` exists (covers/items/logs/streams
/cache/backups). It is the scanner cache for Audiobookshelf, which currently
shares this root with Readarr. The audit ignores it; the reorg script
explicitly excludes it.

## Conclusions

- **`audiobooks/` is mostly fixable mechanically** — 7 of 11 non-conformant
  entries are clean `Author - Title` splits. The remaining 4 need human
  decisions on the canonical author/title pair.
- **`ebooks/` is the bigger problem.** Zero entries are Author-shaped; the
  library is organized as topic shelves (`coding`, `Survival…`) plus a full
  Calibre dump nested at `ebooks/ebooks/calibre/`. Moving everything into
  Readarr's `Author/Title/Title.ext` would require either (a) Calibre-driven
  metadata extraction or (b) manual per-title placement. Neither belongs in
  a mechanical reorg script.
- **One cross-format duplicate confirmed** (Cal Newport / Slow Productivity).
  Once Author folders exist, that title should live at
  `Author/Cal Newport/Slow Productivity/` with both `.epub` and `.mp3`
  alongside (or, if you prefer split libraries, the same path under both
  `audiobooks/` and `ebooks/`).
- **Audiobookshelf coexistence** is fine to leave as-is; its sidecar lives
  outside any title directory.

The companion `books-reorg.sh` codifies only the mechanical renames (F1
audiobook splits, F2 loose-epub authoring) and prints the F3/F4 cases as
manual-review blocks. It will not move anything in dry-run mode.
