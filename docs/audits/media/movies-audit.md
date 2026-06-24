# `/mnt/media/movies` audit — 2026-06-24

Read-only audit of the movies library against the Plex / Jellyfin / Radarr
standard. No file was moved, renamed, or deleted; this report and the
companion `movies-reorg.sh` are the only outputs.

## Standard

One movie per folder, folder named exactly:

```
Title (Year)/Title (Year).<ext>
```

where:

- `Title` matches the canonical release title (no scene tags, language, codec).
- `(Year)` is the 4-digit release year, in parentheses, separated by a single
  space from the title.
- The video file inside has the same basename as the folder and a standard
  video extension (`.mkv`, `.mp4`, `.avi`, `.m4v`, `.mov`, `.m2ts`, …).
- No loose video files at the library root.
- No alternate-cut subdirs at the movie-folder level (Radarr handles
  multi-version via filename suffix, not by subdir).

This is what Radarr's TRaSH-guides default tokens produce (`{Movie Title}
({Release Year})/{Movie Title} ({Release Year})`) and matches what
`domains/media/radarr/sys.nix` mounts at `/movies` (volume
`${config.hwc.paths.media.root}/movies:/movies`).

## Totals

| Metric | Count |
|--------|-------|
| Top-level entries under `/mnt/media/movies` (incl. loose files) | 305 |
| Movie folders (top-level dirs) | 300 |
| Loose files at library root | 5 |
| Folders missing year suffix | 1 |
| Folders with multiple video files | 1 |
| Folders with **no** video file | 1 |
| Folders with implausible / wrong year | 1 |
| Movie folders with subdirs at depth 2 | 2 |
| Single-video folders where file basename == folder name | 174 |
| Single-video folders where file basename ≠ folder name | 124 |

## Nonconformance — folders

### 1. Loose files at library root (5)

These belong in `_misc/` or the prior step's reorganisation archive — Radarr
treats them as orphan content.

```
/mnt/media/movies/REORGANIZATION_LOG.md
/mnt/media/movies/MediaInfo.txt
/mnt/media/movies/Libraries.html
/mnt/media/movies/normalize_movies.py
/mnt/media/movies/strict_clean.sh
```

### 2. Folder missing `(Year)` suffix (1)

```
/mnt/media/movies/The Jungle Book
```

Folder contains two video files for two different releases (see §3); a year is
required to disambiguate. Per Radarr the correct split is
`The Jungle Book (1967)` and `The Jungle Book (...)` based on the second
file's actual year.

### 3. Folders with multiple video files (1)

```
/mnt/media/movies/The Jungle Book/
  The.Jungle.Book.1967.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1-NoTrace.mkv   (4.3 GB)
  The Jungle Book.mkv                                                      (283 MB)
```

Must split into two `Title (Year)/` folders. The small `The Jungle Book.mkv`
needs out-of-band identification (year unknown from filename alone) — flagged
for manual review.

### 4. Folders with no video file (1)

```
/mnt/media/movies/Ice Age - Collision Course (2016)/   (empty)
```

Three other folders (`Duck Soup (1933)`, `Snow Dogs (2002)`,
`Winnie the Pooh - A Very Merry Pooh Year (2002)`) only **looked** empty in a
first pass — each contains a single `.m2ts` rip (`01193.m2ts`, `00045.m2ts`,
`00883.m2ts`). Those are real videos and are flagged under §6 (misnamed),
not here.

### 5. Folders with wrong / implausible year (1)

```
/mnt/media/movies/Blade Runner (2049)/
```

The film *Blade Runner 2049* was released in **2017**; "2049" is the
in-universe setting, not the year. Correct folder name is
`Blade Runner 2049 (2017)` (note also the inner file is already
`Blade.Runner.2049.2017.....mkv`).

### 6. Single-video folders where filename ≠ folder name (124)

Folder name is conformant; the inner file keeps the scene-release name and
needs to be renamed to `<folder>.<ext>`. Examples (full list driven from the
audit, see `movies-reorg.sh`):

```
A Bug's Life (1998)/A.Bugs.Life.1998.1080p.WEBRip.DD+7.1.x264-playHD.mkv
Airplane! (1980)/Airplane.1980.1080p.AMZN.WEB-DL.DDP5.1.H.264-BLOOM.mkv
Aladdin (1992)/Aladdin.1992.NORDiC.1080p.DSNP.WEB-DL.H.264.DDP5.1.Atmos-NoTrace.mkv
A Minecraft Movie (2025)/Un.Film.Minecraft.2025.iTA-ENG.WEB-DL.1080p.x264-CYBER.mkv
Bambi (1942)/Bambi 1942 1080p BluRay x264 DuaL-TURKO.mkv
Beauty and the Beast (1991)/Beauty and the Beast 1991 1080p DSNP WEB-DL DDP5 1 Atmos H 264-BLOOM.mkv
Blade Runner (1982)/Blade.Runner.1982.WEBRip.1080p.x264.EAC3.ITA.ENG.SUB.ITA.ENG-Lullozzo.mkv
Duck Soup (1933)/01193.m2ts
Despicable Me 4 (2024)/Cattivissimo.Me.4.2024.iTA-ENG.Bluray.1080p.x264-CYBER.mkv
Dune - Part Two (2024)/Dune.Parte.Due.2024.iTA-ENG.Bluray.1080p.x264-CYBER.mkv
Forrest Gump (1994)/Forrest.Gump.1994.REPACK.1080p.MGMP.WEB-DL.DDP.5.1.H.264-PiRaTeS.mkv
…
```

Several of these are also **wrong-language titles** (`Un.Film.Minecraft.`,
`Cattivissimo.Me.4.`, `Dune.Parte.Due.`, `Oceania.2.`, `Dragon.Trainer.`) — the
folder name is the canonical English title and is what Radarr/Plex will match
against, so the rename to the folder basename is still the right move.

The full machine-generated list is the input table baked into
`movies-reorg.sh`; running that script with `DRY_RUN=1` (the default) prints
every `mv` it would do.

### 7. Movie-folder subdirs at depth 2 (2)

Radarr expects everything for one movie in the movie folder, not in nested
dirs.

```
/mnt/media/movies/One Hundred and One Dalmatians (1961)/trailers/101 Dalmatians 1969 Theatrical Trailer.mkv
/mnt/media/movies/The Sword in the Stone (1963)/versions/The Sword in the Stone.mkv
```

`trailers/` should be removed (Radarr does not need on-disk trailers in the
movie folder; trailer plugins fetch on demand) **or** the file renamed to
`One Hundred and One Dalmatians (1961)-trailer.mkv` per the Plex extras
convention. `versions/The Sword in the Stone.mkv` looks like a manual second
copy and needs human review — either merge or delete.

## Nonconformance — files (junk)

Across the 300 movie folders there are zero stray `.txt`, `.html`, `.py`,
`.sh`, `.exe`, `.iso`, or unknown extensions inside the movie folders — the
only filetypes present are video (`mkv/mp4/avi/m4v/mov/m2ts`) and standard
metadata sidecars (`srt/sub/idx/nfo/jpg/jpeg/png`). Junk is all at the library
root (§1).

## Summary

- **Structural problems are small in number, large in impact:** 1 missing
  year, 1 multi-movie folder, 1 empty folder, 1 wrong year, 2 nested subdirs.
- **The bulk of the work is cosmetic file renames:** 124 single-video folders
  where only the inner filename needs to match the folder name.
- **Library root needs sweeping:** 5 loose files that don't belong.

Total folders touched by the dry-run plan: **5 root files + 1 folder rename +
1 split + 1 empty-folder review + 1 wrong-year rename + 2 subdir cleanups +
124 file renames = 134 actions**, all printed (not executed) by
`movies-reorg.sh`.
